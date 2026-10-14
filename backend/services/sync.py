"""안전Dream 실종경보 주기 조회와 신규·종료 판단 (DATA_SOURCE=safe182일 때만 동작).

- 서버를 켠 뒤 처음 받은 목록은 기준으로만 저장한다 (신규 아님, 푸시 대상 아님).
- 이후 처음 보는 식별번호이면서 발생일이 최근 7일 이내면 신규 경보 → on_new_alert().
- 한 번 본 식별번호는 다시 신규로 보지 않는다.
- 목록에서 3번 연속 빠지면 "경보종료", 다시 나오면 "수색중". 경보종료는 3일 뒤 응답에서 빠진다.
- 로그에는 건수와 상태 변화 개수만 남긴다. 이름·주소·사진·키·응답 본문은 남기지 않는다.
- 파일에는 식별번호, 시각, 상태, 호출 횟수만 저장한다 (저장소 밖 SYNC_STATE_DIR, 기본 ~/.missing-alert-care).
- 서버 프로세스를 여러 개 띄워도 파일 잠금으로 한 곳에서만 조회한다.
"""
import json
import logging
import math
import os
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path

from services import safe182

KST = timezone(timedelta(hours=9))
DEFAULT_INTERVAL, MIN_INTERVAL = 300, 60
INTERVAL = DEFAULT_INTERVAL  # start()에서 .env의 SAFE182_SYNC_INTERVAL_SEC로 다시 정한다
BACKOFF = [60, 300, 900]  # 실패가 이어질 때 다시 시도하기까지 기다리는 초
DAILY_LIMIT = 1000
WARN_AT = 900
NEW_WITHIN = timedelta(days=7)
MISS_LIMIT = 3
ENDED_VISIBLE = timedelta(days=3)
FORGET_AFTER = timedelta(days=30)  # 경보종료 후 이만큼 지나면 기록을 지운다

SEARCHING, ENDED = "수색중", "경보종료"

log = logging.getLogger("alert-sync")
if not log.handlers:
    _h = logging.StreamHandler()
    _h.setFormatter(logging.Formatter("%(asctime)s [alert-sync] %(levelname)s %(message)s"))
    log.addHandler(_h)
    log.setLevel(logging.INFO)
    log.propagate = False


def _now():
    return datetime.now(KST)


def on_new_alert(alerts):
    """신규 경보가 생기면 불린다. 나중에 FCM 푸시 발송을 여기에 붙인다. 지금은 건수만 남긴다.

    FCM을 붙일 때 주의:
    - 지금은 Tracker.update()가 이 함수를 부르기 전에 notified=True를 먼저 저장한다.
      그대로 두면 발송이 실패한 경보는 다시 보내지 않고 묻힌다.
      발송 성공 후 notified를 기록해야 하고, 실패 건 재전송 처리가 필요하다.
    - alerts에는 실명 등 원본이 들어 있으므로 로그에는 건수만 남긴다.
    """
    log.info("신규 경보 %d건", len(alerts))


def _occr_date(value):
    text = str(value).strip() if value is not None else ""
    if len(text) != 8 or not text.isdigit():
        return None
    try:
        return datetime.strptime(text, "%Y%m%d").date()
    except ValueError:
        return None


class Tracker:
    def __init__(self, state_path=None):
        self.lock = threading.Lock()
        self.state_path = state_path
        self.alerts = {}  # 식별번호 → first_seen, last_seen, notified, status, miss_count, ended_at
        self.raw = {}  # 식별번호 → 마지막으로 받은 원본 (메모리에만, 파일에 저장 안 함)
        self.baseline_done = False
        self.calls = {"date": None, "count": 0, "stopped": False, "warned": False}
        self.problem = None  # 응답에 붙일 안내 (조회 실패, 한도 초과 등)
        self.follower = False  # 다른 프로세스가 조회 담당이면 True
        self.estimated = False  # 하루 예상 호출 수를 이미 로그에 남겼는지
        self._load()

    # 저장 ---------------------------------------------------------------
    def _load(self):
        if not (self.state_path and self.state_path.exists()):
            return
        try:
            data = json.loads(self.state_path.read_text(encoding="utf-8"))
            for sid, a in data.get("alerts", {}).items():
                self.alerts[int(sid)] = {
                    **a,
                    "first_seen": datetime.fromisoformat(a["first_seen"]),
                    "last_seen": datetime.fromisoformat(a["last_seen"]),
                    "ended_at": datetime.fromisoformat(a["ended_at"]) if a.get("ended_at") else None,
                }
            self.calls.update(data.get("calls", {}))
        except (OSError, ValueError, KeyError, TypeError):
            log.warning("상태 파일을 읽지 못해 새로 시작합니다")
            self.alerts = {}

    def _save(self):
        if not self.state_path:
            return
        data = {
            "alerts": {str(sid): {**a, "first_seen": a["first_seen"].isoformat(), "last_seen": a["last_seen"].isoformat(),
                                  "ended_at": a["ended_at"].isoformat() if a["ended_at"] else None}
                       for sid, a in self.alerts.items()},
            "calls": self.calls,
        }
        tmp = self.state_path.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        tmp.replace(self.state_path)

    # 호출 횟수 -------------------------------------------------------------
    def _roll_day(self, now):
        today = now.date().isoformat()
        if self.calls["date"] != today:
            self.calls = {"date": today, "count": 0, "stopped": False, "warned": False}

    def count_call(self, now=None):
        with self.lock:
            now = now or _now()
            self._roll_day(now)
            self.calls["count"] += 1
            if self.calls["count"] >= WARN_AT and not self.calls["warned"]:
                self.calls["warned"] = True
                log.warning("오늘 호출 %d회 — 일일 한도 %d회에 가까워졌습니다", self.calls["count"], DAILY_LIMIT)
            self._save()

    def stopped_today(self, now):
        with self.lock:
            self._roll_day(now)
            return self.calls["stopped"]

    def stop_today(self, now):
        with self.lock:
            self._roll_day(now)
            self.calls["stopped"] = True
            self.problem = "오늘 안전Dream 호출 한도를 넘어 조회를 멈췄습니다. 내일 다시 조회합니다."
            self._save()

    # 비교 ---------------------------------------------------------------
    def update(self, rows, now):
        """새 목록과 비교한다. (신규 경보 원본들, 변화 개수) 를 돌려준다."""
        current = {r["msspsnIdntfccd"]: r for r in rows}
        new, changes = [], {"baseline": 0, "old": 0, "new": 0, "restored": 0, "candidate": 0, "ended": 0}
        with self.lock:
            baseline = not self.baseline_done
            self.raw.update(current)
            for sid, r in current.items():
                a = self.alerts.get(sid)
                if a is None:
                    occr = _occr_date(r.get("occrde"))
                    is_new = not baseline and occr is not None and now.date() - occr <= NEW_WITHIN
                    self.alerts[sid] = {"first_seen": now, "last_seen": now, "notified": is_new,
                                        "status": SEARCHING, "miss_count": 0, "ended_at": None}
                    if is_new:
                        new.append(r)
                    else:  # 처음 켰을 때의 기준 목록, 또는 발생일이 오래됐거나 알 수 없는 새 번호
                        changes["baseline" if baseline else "old"] += 1
                    continue
                a["last_seen"], a["miss_count"] = now, 0
                if a["status"] == ENDED:
                    a["status"], a["ended_at"] = SEARCHING, None
                    changes["restored"] += 1
            for sid, a in list(self.alerts.items()):
                if sid in current:
                    continue
                if a["status"] == SEARCHING:
                    a["miss_count"] += 1
                    if a["miss_count"] >= MISS_LIMIT:
                        a["status"], a["ended_at"] = ENDED, now
                        changes["ended"] += 1
                    else:
                        changes["candidate"] += 1
                elif a["ended_at"] and now - a["ended_at"] > FORGET_AFTER:
                    del self.alerts[sid]
                    self.raw.pop(sid, None)
            self.baseline_done = True
            self.problem = None
            self._save()
        changes["new"] = len(new)
        return new, changes

    # 응답용 ---------------------------------------------------------------
    def snapshot(self, now=None):
        now = now or _now()
        with self.lock:
            if self.follower:
                return [], "이 서버 프로세스는 조회 담당이 아닙니다. 실제 데이터 모드에서는 서버를 하나만 띄워 주세요."
            if not self.baseline_done:
                return [], self.problem or "아직 실제 데이터를 받아오지 못했습니다. 잠시 후 다시 시도해 주세요."
            items = []
            for sid, a in self.alerts.items():
                r = self.raw.get(sid)
                if r is None:  # 재시작 전에 종료된 경보는 원본이 없어 보여줄 수 없다
                    continue
                if a["status"] == ENDED:
                    if now - a["ended_at"] > ENDED_VISIBLE:
                        continue
                    r = {**r, "nm": None, "tknphotoFile": None, "tknphotolength": 0}  # 종료된 경보는 이름·사진 제외
                items.append(r)
            return items, self.problem

    def status_of(self, sid):
        with self.lock:
            a = self.alerts.get(sid)
            return a["status"] if a else SEARCHING


TRACKER = Tracker()


def estimate_daily_calls(total, interval):
    """(회차당 호출 수, 하루 예상 호출 수, 한도 경고선 아래로 두려면 필요한 최소 간격 초)."""
    pages = max(1, math.ceil(total / safe182.ROW_SIZE))
    daily = math.ceil(86400 / interval) * pages
    need = max(MIN_INTERVAL, math.ceil(86400 * pages / WARN_AT))
    return pages, daily, need


def _log_estimate(tracker, total):
    """첫 조회 뒤 한 번만, 전체 건수로 하루 예상 호출 수를 남기고 경고선을 넘으면 경고한다."""
    if tracker.estimated:
        return
    tracker.estimated = True
    pages, daily, need = estimate_daily_calls(total, INTERVAL)
    log.info("하루 예상 호출 %d회 (전체 %d건 → 회차당 %d번 호출, 조회 간격 %d초)", daily, total, pages, INTERVAL)
    if daily > WARN_AT:
        log.warning("하루 예상 호출이 %d회를 넘습니다. 간격을 %d초 이상으로 늘려야 합니다 (SAFE182_SYNC_INTERVAL_SEC)",
                    WARN_AT, need)


def poll_once(tracker, api_id, api_key, failures, now=None, fetch=safe182.fetch_all):
    """한 회차 조회. (다음 조회까지 기다릴 초, 연속 실패 횟수) 를 돌려준다."""
    now = now or _now()
    if tracker.stopped_today(now):
        midnight = datetime.combine(now.date() + timedelta(days=1), datetime.min.time(), KST)
        return max(60, int((midnight - now).total_seconds())), failures
    try:
        rows, received, total, skipped = fetch(api_id, api_key, lambda: tracker.count_call(now))
    except safe182.DailyLimitExceeded as e:
        tracker.stop_today(now)
        log.warning("%s — 오늘은 조회를 멈춥니다", e)
        return poll_once(tracker, api_id, api_key, 0, now, fetch)
    except safe182.Safe182Error as e:
        failures += 1
        wait = BACKOFF[min(failures, len(BACKOFF)) - 1]
        with tracker.lock:
            tracker.problem = "최근 실제 데이터 조회에 실패해 마지막으로 받은 목록을 보여줍니다."
        log.warning("조회 실패 %d회째: %s — %d초 뒤 다시 시도", failures, e, wait)
        return wait, failures
    _log_estimate(tracker, total)
    if skipped:
        log.warning("형식이 맞지 않는 항목 %d건을 건너뛰었습니다", skipped)
    if received != total:
        log.warning("받은 건수 %d ≠ totalCount %d — 이번 회차는 비교에 쓰지 않습니다", received, total)
        return INTERVAL, 0
    new, ch = tracker.update(rows, now)
    log.info("조회 완료: 전체 %d건 | 기준 %d, 신규 %d, 오래된 새 번호 %d, 종료후보 %d, 경보종료 %d, 복구 %d | 오늘 호출 %d회",
             len(rows), ch["baseline"], ch["new"], ch["old"], ch["candidate"], ch["ended"], ch["restored"],
             tracker.calls["count"])
    if new:
        on_new_alert(new)
    return INTERVAL, 0


def read_interval(value):
    """SAFE182_SYNC_INTERVAL_SEC 값 → (쓸 간격 초, 설명). 비었거나 숫자가 아니거나 0 이하면 기본값, 60초 미만이면 60초."""
    text = (value or "").strip()
    try:
        sec = int(text)
    except ValueError:
        return DEFAULT_INTERVAL, "숫자가 아니어서 기본값 사용" if text else "설정이 없거나 비어 있어 기본값 사용"
    if sec <= 0:
        return DEFAULT_INTERVAL, "0 이하라서 기본값 사용"
    if sec < MIN_INTERVAL:
        return MIN_INTERVAL, f"{MIN_INTERVAL}초보다 짧아 {MIN_INTERVAL}초로 올림"
    return sec, ".env 설정값"


def start():
    """서버 시작 시 부른다. 조회 담당이 되면 백그라운드 조회를 시작하고, 멈추는 함수를 돌려준다."""
    global INTERVAL
    api_id, api_key = os.getenv("MISSING_ALERT_API_ID"), os.getenv("MISSING_ALERT_API_KEY")
    if not (api_id and api_key):
        TRACKER.problem = "MISSING_ALERT_API_ID / MISSING_ALERT_API_KEY가 없어 실제 데이터를 조회할 수 없습니다."
        log.error("MISSING_ALERT_API_ID / MISSING_ALERT_API_KEY가 없어 조회를 시작하지 않습니다")
        return None

    import fcntl  # 맥·리눅스 전용이라 여기서만 불러온다 (sample 모드는 윈도우에서도 켜지게)

    state_dir = Path(os.getenv("SYNC_STATE_DIR") or Path.home() / ".missing-alert-care")
    state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock_file = open(state_dir / "safe182-sync.lock", "w")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)  # 프로세스가 끝나면 자동으로 풀린다
    except BlockingIOError:
        lock_file.close()
        TRACKER.follower = True
        log.warning("다른 서버 프로세스가 이미 조회 중이라 이 프로세스는 조회하지 않습니다")
        return None

    TRACKER.__init__(state_dir / "safe182-state.json")  # 저장된 상태(식별번호·시각·상태·호출 횟수) 불러오기
    INTERVAL, why = read_interval(os.getenv("SAFE182_SYNC_INTERVAL_SEC"))
    stop = threading.Event()

    def loop():
        failures = 0
        while not stop.is_set():
            try:
                wait, failures = poll_once(TRACKER, api_id, api_key, failures)
            except Exception as e:  # 예상 못 한 오류에도 조회를 멈추지 않는다 (내용 대신 종류만 남김)
                failures += 1
                wait = BACKOFF[min(failures, len(BACKOFF)) - 1]
                log.error("예상하지 못한 오류(%s) — %d초 뒤 다시 시도", type(e).__name__, wait)
            stop.wait(wait)

    threading.Thread(target=loop, name="safe182-sync", daemon=True).start()
    log.info("안전Dream 조회 시작 — 조회 간격 %d초 (%s)", INTERVAL, why)

    def shutdown():
        stop.set()
        lock_file.close()

    return shutdown
