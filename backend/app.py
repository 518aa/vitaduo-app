"""
VitaDuo Backend Server
Flask + SocketIO RESTful API
"""
import os
import json
import uuid
import random
import re
import threading
import time
import urllib.request
import urllib.error
import urllib.parse
import hashlib
import socket
from collections import OrderedDict, deque
from concurrent.futures import ThreadPoolExecutor
import logging

logger = logging.getLogger('vitaduo')
import resource
from dotenv import load_dotenv

# 加载环境变量
load_dotenv()

from datetime import datetime, timedelta
from functools import wraps
try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None

class LocalTTLCache:
    def __init__(self, max_size=2048, ttl=600):
        self.max_size = max_size
        self.ttl = ttl
        self.data = OrderedDict()
        self.expire_at = {}
        self.lock = threading.Lock()

    def get(self, key):
        now = time.time()
        with self.lock:
            expire_at = self.expire_at.get(key)
            if expire_at is None or expire_at < now:
                if key in self.data:
                    self.data.pop(key, None)
                self.expire_at.pop(key, None)
                return None
            value = self.data.get(key)
            if value is None:
                return None
            self.data.move_to_end(key)
            return value

    def set(self, key, value, ttl=None):
        ttl_value = ttl if ttl is not None else self.ttl
        expire_at = time.time() + ttl_value
        with self.lock:
            if key in self.data:
                self.data.move_to_end(key)
            self.data[key] = value
            self.expire_at[key] = expire_at
            while len(self.data) > self.max_size:
                oldest_key, _ = self.data.popitem(last=False)
                self.expire_at.pop(oldest_key, None)

class MultiLevelCache:
    def __init__(self, local_cache, redis_client=None, redis_ttl=600, prefix="cache:"):
        self.local_cache = local_cache
        self.redis_client = redis_client
        self.redis_ttl = redis_ttl
        self.prefix = prefix

    def _redis_key(self, key):
        return f"{self.prefix}{key}"

    def get(self, key):
        value = self.local_cache.get(key)
        if value is not None:
            return value
        if not self.redis_client:
            return None
        try:
            cached = self.redis_client.get(self._redis_key(key))
        except Exception:
            return None
        if cached is None:
            return None
        self.local_cache.set(key, cached)
        return cached

    def set(self, key, value, ttl=None):
        self.local_cache.set(key, value, ttl=ttl)
        if not self.redis_client:
            return
        cache_ttl = ttl if ttl is not None else self.redis_ttl
        try:
            self.redis_client.setex(self._redis_key(key), int(cache_ttl), value)
        except Exception:
            return

class TokenBucket:
    def __init__(self, capacity, refill_rate):
        self.capacity = capacity
        self.refill_rate = refill_rate
        self.tokens = {}
        self.updated_at = {}
        self.lock = threading.Lock()

    def allow(self, key):
        now = time.time()
        with self.lock:
            tokens = self.tokens.get(key, self.capacity)
            updated_at = self.updated_at.get(key, now)
            delta = max(0.0, now - updated_at)
            tokens = min(self.capacity, tokens + delta * self.refill_rate)
            if tokens < 1.0:
                self.tokens[key] = tokens
                self.updated_at[key] = now
                return False
            tokens -= 1.0
            self.tokens[key] = tokens
            self.updated_at[key] = now
            return True

class PerfTracker:
    def __init__(self, window_seconds=300, max_samples=10000):
        self.window_seconds = window_seconds
        self.max_samples = max_samples
        self.data = {}
        self.lock = threading.Lock()

    def record(self, key, duration):
        now = time.time()
        with self.lock:
            samples = self.data.setdefault(key, deque())
            samples.append((now, duration))
            while samples and now - samples[0][0] > self.window_seconds:
                samples.popleft()
            while len(samples) > self.max_samples:
                samples.popleft()

    def summary(self, key, window_seconds=60):
        now = time.time()
        with self.lock:
            samples = list(self.data.get(key, []))
        recent = [d for t, d in samples if now - t <= window_seconds]
        count = len(recent)
        if count == 0:
            return {
                "count": 0,
                "qps": 0.0,
                "avg_ms": 0.0,
                "p50_ms": 0.0,
                "p95_ms": 0.0,
                "p99_ms": 0.0
            }
        recent.sort()
        def percentile(p):
            idx = int(round((len(recent) - 1) * p))
            return recent[min(max(idx, 0), len(recent) - 1)]
        return {
            "count": count,
            "qps": count / float(window_seconds),
            "avg_ms": sum(recent) / count * 1000.0,
            "p50_ms": percentile(0.50) * 1000.0,
            "p95_ms": percentile(0.95) * 1000.0,
            "p99_ms": percentile(0.99) * 1000.0
        }

def _profile_call(name, func, *args, **kwargs):
    if not os.getenv("PERF_PROFILE"):
        return func(*args, **kwargs)
    import cProfile
    prof = cProfile.Profile()
    result = prof.runcall(func, *args, **kwargs)
    output_dir = os.getenv("PERF_PROFILE_DIR", "/tmp")
    filename = f"{name}_{int(time.time() * 1000)}.prof"
    try:
        os.makedirs(output_dir, exist_ok=True)
        prof.dump_stats(os.path.join(output_dir, filename))
    except Exception:
        pass
    return result

def _build_redis_client():
    try:
        import redis
    except Exception:
        return None
    cluster_urls = os.getenv("REDIS_CLUSTER_URLS")
    if cluster_urls:
        try:
            from urllib.parse import urlparse
            from redis.cluster import RedisCluster
            startup_nodes = []
            for item in cluster_urls.split(","):
                item = item.strip()
                if not item:
                    continue
                if "://" not in item:
                    item = f"redis://{item}"
                parsed = urlparse(item)
                if not parsed.hostname or not parsed.port:
                    continue
                startup_nodes.append({"host": parsed.hostname, "port": parsed.port})
            if startup_nodes:
                return RedisCluster(startup_nodes=startup_nodes, decode_responses=True)
        except Exception:
            return None
    redis_url = os.getenv("REDIS_URL")
    if redis_url:
        try:
            return redis.Redis.from_url(redis_url, decode_responses=True)
        except Exception:
            return None
    return None

from flask import Flask, request, jsonify, g
from flask_jwt_extended import (
    JWTManager, create_access_token, jwt_required, get_jwt_identity, get_jwt
)
from flask_cors import CORS
from flask_socketio import SocketIO, emit, join_room, leave_room, rooms
from werkzeug.security import generate_password_hash, check_password_hash
from sqlalchemy import inspect, or_, func
from sqlalchemy.orm import aliased

from config import config
from models import (
    db, User, Question, QuestionAnswer, Match, ChatMessage, Rating, Purchase, MatchCode,
    UserReport, BlockedUser, DailyCardInteraction
)
from matching import (
    MatchingAlgorithm, generate_match_code, check_unlock_status, unlock_match_profile
)

REDIS_CLIENT = _build_redis_client()
TRANSLATE_LOCAL_CACHE = LocalTTLCache(
    max_size=int(os.getenv("TRANSLATE_CACHE_SIZE", "4096")),
    ttl=int(os.getenv("TRANSLATE_CACHE_TTL", "86400"))
)
TRANSLATE_CACHE = MultiLevelCache(
    TRANSLATE_LOCAL_CACHE,
    redis_client=REDIS_CLIENT,
    redis_ttl=int(os.getenv("REDIS_TRANSLATE_TTL", "86400")),
    prefix="translate:"
)

CHAT_RATE_LIMIT = int(os.getenv("CHAT_RATE_LIMIT_PER_MIN", "60"))
TRANSLATE_RATE_LIMIT = int(os.getenv("TRANSLATE_RATE_LIMIT_PER_MIN", "30"))
CHAT_LIMITER = TokenBucket(CHAT_RATE_LIMIT, CHAT_RATE_LIMIT / 60.0)
TRANSLATE_LIMITER = TokenBucket(TRANSLATE_RATE_LIMIT, TRANSLATE_RATE_LIMIT / 60.0)

AI_WORKERS = int(os.getenv("AI_WORKERS", "4"))
AI_INFLIGHT = int(os.getenv("AI_INFLIGHT", "32"))
AI_EXECUTOR = ThreadPoolExecutor(max_workers=AI_WORKERS)
AI_SEMAPHORE = threading.Semaphore(AI_INFLIGHT)

TRANSLATE_QUEUE = deque()
TRANSLATE_TASKS = {}
TRANSLATE_LOCK = threading.Lock()
TRANSLATE_EVENT = threading.Event()
TRANSLATE_BATCH_SIZE = int(os.getenv("TRANSLATE_BATCH_SIZE", "8"))
TRANSLATE_BATCH_WINDOW = float(os.getenv("TRANSLATE_BATCH_WINDOW", "0.2"))
TRANSLATE_WORKER_STARTED = False

PERF_TRACKER = PerfTracker(
    window_seconds=int(os.getenv("PERF_WINDOW_SECONDS", "300")),
    max_samples=int(os.getenv("PERF_MAX_SAMPLES", "10000"))
)
PERF_ENDPOINTS = {
    "/api/chat/send": "chat_send",
    "/api/translate": "translate",
    "/api/translate/result": "translate_result"
}

# 初始化问卷题目 (仅第一次)
def _init_questions():
    count = Question.query.count()
    if count < 66:
        if count > 0:
            logger.info(f"检测到题库数量不完整({count}/66), 正在清空并重新导入...")
            try:
                Question.query.delete()
                db.session.commit()
            except Exception as e:
                db.session.rollback()
                logger.error(f"清空题库失败: {e}")
                return
        logger.info("初始化问卷题目: 开始导入 schema.sql 中的题库...")
        try:
            inspector = inspect(db.engine)
            columns = [col["name"] for col in inspector.get_columns("questions")]
            has_weight = "weight" in columns
            if not has_weight:
                logger.info("检测到 questions 表缺少 weight 列, 正在添加...")
                try:
                    db.session.execute(db.text("ALTER TABLE questions ADD COLUMN weight FLOAT DEFAULT 1.0 NOT NULL;"))
                    db.session.commit()
                    logger.info("weight 列添加成功")
                except Exception as e:
                    db.session.rollback()
                    logger.error(f"添加 weight 列失败: {e}")

            # 加载 schema.sql 中的 INSERT 语句
            base_dir = os.path.dirname(os.path.abspath(__file__))
            schema_path = os.path.join(base_dir, "schema.sql")
            if not os.path.exists(schema_path):
                logger.warning("未找到 schema.sql, 跳过自动导入")
                return

            with open(schema_path, "r", encoding="utf-8") as f:
                sql_lines = f.read().splitlines()

            # 提取 INSERT INTO questions ... VALUES ... ; 块
            insert_lines = []
            recording = False
            for line in sql_lines:
                stripped = line.strip()
                if stripped.upper().startswith("INSERT INTO QUESTIONS"):
                    recording = True
                    insert_lines.append(line)
                    continue
                if recording:
                    if stripped.startswith("--"):
                        continue
                    insert_lines.append(line)
                    if ";" in line:
                        break

            if not insert_lines:
                logger.warning("schema.sql 中未找到题目 INSERT 语句, 跳过导入")
                return

            insert_sql = "\n".join(insert_lines)
            upper_sql = insert_sql.upper()
            if "VALUES" not in upper_sql:
                logger.warning("题库 INSERT 语句缺少 VALUES, 跳过导入")
                return

            values_sql = insert_sql[upper_sql.index("VALUES") + len("VALUES"):].strip()
            if values_sql.endswith(";"):
                values_sql = values_sql[:-1]

            def parse_tuples(s):
                tuples = []
                in_string = False
                depth = 0
                start = None
                i = 0
                while i < len(s):
                    ch = s[i]
                    if ch == "'":
                        if in_string:
                            if i + 1 < len(s) and s[i + 1] == "'":
                                i += 1
                            else:
                                in_string = False
                        else:
                            in_string = True
                    elif not in_string:
                        if ch == "(":
                            if depth == 0:
                                start = i + 1
                            depth += 1
                        elif ch == ")":
                            depth -= 1
                            if depth == 0 and start is not None:
                                tuples.append(s[start:i])
                                start = None
                    i += 1
                return tuples

            def parse_fields(content):
                fields = []
                buf = []
                in_string = False
                i = 0
                while i < len(content):
                    ch = content[i]
                    if ch == "'":
                        if in_string:
                            if i + 1 < len(content) and content[i + 1] == "'":
                                buf.append("'")
                                i += 1
                            else:
                                in_string = False
                        else:
                            in_string = True
                    elif ch == "," and not in_string:
                        fields.append("".join(buf).strip())
                        buf = []
                    else:
                        buf.append(ch)
                    i += 1
                if buf:
                    fields.append("".join(buf).strip())
                return fields

            def convert_value(raw):
                if raw is None:
                    return None
                if raw.upper() == "NULL":
                    return None
                if raw.upper() == "TRUE":
                    return True
                if raw.upper() == "FALSE":
                    return False
                if raw.startswith("'") and raw.endswith("'"):
                    return raw[1:-1]
                if raw.startswith('"') and raw.endswith('"'):
                    return raw[1:-1]
                try:
                    if "." in raw:
                        return float(raw)
                    return int(raw)
                except Exception:
                    return raw

            tuples = parse_tuples(values_sql)
            if not tuples:
                logger.warning("未解析到题目数据, 跳过导入")
                return

            for t in tuples:
                fields = parse_fields(t)
                if len(fields) < 7:
                    continue
                values = [convert_value(f) for f in fields]
                q = Question(
                    id=int(values[0]),
                    text_cn=values[1],
                    text_en=values[2],
                    section=values[3],
                    question_type=values[4],
                    is_sensitive=bool(values[5]),
                    weight=float(values[6]) if values[6] is not None else 1.0
                )
                db.session.add(q)
            db.session.commit()
            logger.info(f"题库导入完成, 共插入 {len(tuples)} 道题目")
        except Exception as e:
            db.session.rollback()
            logger.error(f"初始化题库时发生异常: {e}")

def _ensure_user_columns():
    inspector = inspect(db.engine)
    columns = [col["name"] for col in inspector.get_columns("users")]
    if "is_ai" not in columns:
        db.session.execute(db.text("ALTER TABLE users ADD COLUMN is_ai BOOLEAN DEFAULT 0 NOT NULL;"))
    if "ai_profile" not in columns:
        db.session.execute(db.text("ALTER TABLE users ADD COLUMN ai_profile TEXT NULL;"))
    db.session.commit()

def _migrate_seed_ai_users():
    """One-time migration: mark @vitaduo.ai users as AI and populate ai_profile."""
    users = User.query.filter(
        User.contact.like("%@vitaduo.ai"),
        User.is_ai == False  # noqa: E712
    ).all()
    if not users:
        return
    from matching import generate_match_code
    existing_codes = {c for (c,) in db.session.query(MatchCode.code).all()}
    updated = 0
    for user in users:
        user.is_ai = True
        is_chinese = bool(user.city and any("\u4e00" <= ch <= "\u9fff" for ch in user.city))
        persona = random.choice(CHINESE_PERSONAS if is_chinese else (
            "Love traveling and food, gentle and detail-oriented",
            "Passionate about sports and music, optimistic and outgoing",
            "Prefer quiet reading, rational with good boundaries",
            "Enjoy photography and movies, slow to warm up but genuine",
            "Value quality of life, good at communication and listening",
            "Responsible, value family and companionship",
            "Love exploring city corners, always discovering new things",
            "Serious at work, love cooking at home"
        ))
        parts = (user.city or "").split("\u00b7")
        country = parts[0].strip() if len(parts) >= 1 else ""
        city = parts[1].strip() if len(parts) >= 2 else (user.city or "")
        user.ai_profile = json.dumps({
            "nickname": user.nickname,
            "age": user.age,
            "gender": user.gender,
            "country": country,
            "city": city,
            "school_career": user.school_career or "",
            "persona": persona,
            "language": "中文" if is_chinese else "英语"
        }, ensure_ascii=False)
        if not MatchCode.query.filter_by(user_id=user.id).first():
            code = generate_match_code()
            while code in existing_codes:
                code = generate_match_code()
            existing_codes.add(code)
            db.session.add(MatchCode(user_id=user.id, code=code, is_active=True))
        updated += 1
    db.session.commit()
    logger.info(f"AI migration: marked {updated} users as AI")


def _ensure_chat_indexes():
    inspector = inspect(db.engine)
    existing = {idx.get("name") for idx in inspector.get_indexes("chat_messages")}
    statements = {
        "idx_chat_messages_match_created": "CREATE INDEX idx_chat_messages_match_created ON chat_messages (match_id, created_at, id)",
        "idx_chat_messages_match_sender": "CREATE INDEX idx_chat_messages_match_sender ON chat_messages (match_id, sender_id)",
        "idx_chat_messages_match_read": "CREATE INDEX idx_chat_messages_match_read ON chat_messages (match_id, is_read)"
    }
    for name, sql in statements.items():
        if name in existing:
            continue
        db.session.execute(db.text(sql))
    db.session.commit()

def _ensure_moderation_tables():
    """Create user_reports and blocked_users tables if they don't exist — Apple Guideline 1.2"""
    inspector = inspect(db.engine)
    existing_tables = inspector.get_table_names()
    if 'user_reports' not in existing_tables or 'blocked_users' not in existing_tables:
        db.create_all()

def _extract_json_array(text):
    if not text:
        return None
    start = text.find("[")
    end = text.rfind("]")
    if start == -1 or end == -1 or end <= start:
        return None
    snippet = text[start:end + 1]
    try:
        return json.loads(snippet)
    except Exception:
        return None

def _parse_seed_payload(content):
    if not content:
        return None
    try:
        parsed = json.loads(content)
        if isinstance(parsed, list):
            return parsed
        if isinstance(parsed, dict):
            for key in ["data", "items", "users", "results"]:
                value = parsed.get(key)
                if isinstance(value, list):
                    return value
    except Exception:
        pass
    return _extract_json_array(content)

def _glm_chat(messages, temperature=0.7, timeout=180):
    mock_response = os.getenv("GLM_MOCK_RESPONSE")
    if mock_response:
        return mock_response
    api_key = os.getenv("GLM_API_KEY")
    base_url = os.getenv("GLM_API_BASE")
    model = os.getenv("GLM_MODEL", "glm-4.7")
    timeout = int(os.getenv("GLM_TIMEOUT", str(timeout)))
    if not api_key or not base_url:
        logger.warning(f"glm_chat: missing config key={bool(api_key)} base={bool(base_url)}")
        return None
    logger.info(f"glm_chat: calling {base_url} model={model} msgs={len(messages)}")
    payload = json.dumps({
        "model": model,
        "messages": messages,
        "temperature": temperature
    }).encode("utf-8")

    parsed = urllib.parse.urlparse(base_url)
    host = parsed.hostname
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    path = parsed.path or "/"
    if parsed.query:
        path += "?" + parsed.query

    # Resolve DNS with optional IP override (for Render free tier DNS failures)
    dns_overrides = {}
    _dns_str = os.getenv("DNS_OVERRIDES", "")
    if _dns_str:
        for pair in _dns_str.split(","):
            if "=" in pair:
                d, ip = pair.split("=", 1)
                dns_overrides[d.strip()] = ip.strip()
    connect_ip = dns_overrides.get(host, None)

    try:
        import http.client
        import ssl
        import socket as _socket

        # Create socket with IP override or normal DNS
        if connect_ip:
            sock = _socket.create_connection((connect_ip, port), timeout=timeout)
            if parsed.scheme == "https":
                ctx = ssl.create_default_context()
                ctx.server_hostname = host
                sock = ctx.wrap_socket(sock, server_hostname=host)
        else:
            sock = _socket.create_connection((host, port), timeout=timeout)
            if parsed.scheme == "https":
                ctx = ssl.create_default_context()
                sock = ctx.wrap_socket(sock, server_hostname=host)

        conn = http.client.HTTPConnection(host, port, timeout=timeout)
        conn.sock = sock
        conn.request("POST", path, body=payload, headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
            "Host": host
        })
        resp = conn.getresponse()
        raw = resp.read().decode("utf-8")
        conn.close()
        if resp.status >= 400:
            logger.error(f"glm HTTP {resp.status}: {raw[:500]}")
            return f"__GLM_ERROR__:{raw[:200]}"
        response_data = json.loads(raw)
    except Exception as exc:
        logger.error(f"glm request failed: {exc}", exc_info=True)
        return None

    if isinstance(response_data, dict):
        choices = response_data.get("choices") or response_data.get("data") or []
        if choices and isinstance(choices[0], dict):
            message = choices[0].get("message") or {}
            content = (
                message.get("content")
                or choices[0].get("content")
                or choices[0].get("text")
            )
            if content:
                logger.info(f"glm_chat: got reply len={len(content)}")
                return content
    logger.warning(f"glm response invalid: {str(response_data)[:300]}")
    return None

CHINESE_NICKNAMES = (
    "小雨", "阿泽", "安然", "小北", "子涵", "可心", "雨桐", "嘉宁", "星宇", "晨曦",
    "沐辰", "佳音", "子墨", "若曦", "思远", "依诺", "子晴", "允熙", "语嫣", "知夏"
)
CHINESE_CITIES = (
    "北京", "上海", "广州", "深圳", "杭州", "南京", "成都", "重庆", "武汉", "西安",
    "苏州", "天津", "长沙", "青岛", "厦门", "合肥", "郑州", "沈阳", "大连", "宁波"
)
CHINESE_SCHOOL_CAREERS = (
    "互联网产品经理", "数据分析师", "软件工程师", "市场运营", "品牌策划",
    "金融分析师", "高校教师", "医生", "建筑设计师", "新媒体编辑",
    "清华大学", "北京大学", "复旦大学", "浙江大学", "上海交通大学",
    "中山大学", "武汉大学", "厦门大学", "南京大学", "中国人民大学"
)
CHINESE_PERSONAS = (
    "喜欢旅行和美食，性格温和细致", "热爱运动和音乐，乐观开朗",
    "偏好安静阅读，理性且有边界感", "喜欢摄影和电影，慢热但真诚",
    "注重生活品质，擅长沟通与倾听", "有责任感，重视家庭与陪伴",
    "热衷探索城市角落，喜欢发现新鲜事", "工作认真，生活里爱做饭"
)

def _contains_chinese(text):
    if not text:
        return False
    return any("\u4e00" <= ch <= "\u9fff" for ch in str(text))

def _looks_chinese_user(country, city, locale):
    locale_value = str(locale or "").lower()
    if locale_value in ["zh", "zh-cn", "zh-hans", "zh-hant", "cn", "中文", "china", "chinese"]:
        return True
    combined = f"{country or ''} {city or ''}"
    if _contains_chinese(combined):
        return True
    lower = combined.lower()
    if "china" in lower or "prc" in lower or "cn" in lower:
        return True
    if "中国" in combined:
        return True
    return False

def _normalize_chinese_profile(nickname, country, city, school_career, persona):
    if not _contains_chinese(nickname):
        nickname = random.choice(CHINESE_NICKNAMES)
    if not _contains_chinese(country):
        country = "中国"
    if not _contains_chinese(city):
        city = random.choice(CHINESE_CITIES)
    if not _contains_chinese(school_career):
        school_career = random.choice(CHINESE_SCHOOL_CAREERS)
    if not _contains_chinese(persona):
        persona = random.choice(CHINESE_PERSONAS)
    return nickname, country, city, school_career, persona

def _build_seed_prompt(batch_size, max_values, locale="mix"):
    locale_value = str(locale or "mix").lower()
    locale_hint = ""
    if locale_value in ["zh", "zh-cn", "zh-hans", "zh-hant", "中文", "china", "chinese", "cn"]:
        locale_hint = "生成中文用户，所有字段使用中文填写。"
    elif locale_value in ["en", "en-us", "en-gb", "english"]:
        locale_hint = "生成英文用户，所有字段使用英文填写。"
    return (
        "生成{count}个用户资料与问卷答案，输出严格JSON数组，不要Markdown。"
        "每个对象字段: nickname, age(18-45), gender(male/female), country, city, "
        "school_career, contact, persona, answers(长度66整数数组)。"
        "answers[i]必须在1到max_values[i]之间。"
        "要求：男女各半，中国、美国与其他国家都有，行业/学校/地区尽量真实。"
        "contact需是唯一邮箱样式。"
        "{locale_hint}"
        "若country或city为中文用户，则nickname/country/city/school_career/persona全部中文。"
        "max_values={max_values}"
    ).format(count=batch_size, max_values=max_values, locale_hint=locale_hint)

def _sanitize_answer(value, max_value):
    try:
        val = int(value)
    except Exception:
        return None
    if val < 1:
        return 1
    if val > max_value:
        return max_value
    return val

def _ensure_match_code(user_id):
    existing = MatchCode.query.filter_by(user_id=user_id).first()
    if existing:
        return existing
    code = generate_match_code()
    while MatchCode.query.filter_by(code=code).first():
        code = generate_match_code()
    match_code = MatchCode(user_id=user_id, code=code)
    db.session.add(match_code)
    return match_code

def _parse_ai_profile(raw):
    if not raw:
        return {}
    if isinstance(raw, dict):
        return raw
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        pass
    return {"persona": str(raw)}

def _infer_ai_reply_language(profile, ai_user):
    explicit = (profile.get("language") or profile.get("lang") or "").strip()
    if explicit:
        return explicit
    country = str(profile.get("country") or "")
    city = str(profile.get("city") or ai_user.city or "")
    combined = f"{country} {city}"
    lower = combined.lower()
    if any(k in combined for k in ["中国", "北京", "上海", "广州", "深圳", "杭州", "南京", "成都", "重庆", "武汉", "西安", "苏州", "天津", "长沙"]):
        return "中文"
    if any(k in lower for k in ["china", "prc", "cn"]):
        return "中文"
    if "美国" in combined or "united states" in lower or "usa" in lower:
        return "英语"
    if "英国" in combined or any(k in lower for k in ["united kingdom", "uk", "england", "scotland", "wales", "ireland"]):
        return "英语"
    if "加拿大" in combined or "canada" in lower:
        return "英语"
    if "澳大利亚" in combined or "australia" in lower or "new zealand" in lower:
        return "英语"
    if "法国" in combined or "france" in lower:
        return "法语"
    if "德国" in combined or "germany" in lower:
        return "德语"
    if "西班牙" in combined or "spain" in lower:
        return "西班牙语"
    if "意大利" in combined or "italy" in lower:
        return "意大利语"
    if "日本" in combined or "japan" in lower:
        return "日语"
    if "韩国" in combined or "korea" in lower:
        return "韩语"
    if "俄罗斯" in combined or "russia" in lower:
        return "俄语"
    if "巴西" in combined or "葡萄牙" in combined or "brazil" in lower or "portugal" in lower:
        return "葡萄牙语"
    if "印度" in combined or "india" in lower:
        return "英语"
    return "英语"

def _normalize_translate_language(target_lang):
    if not target_lang:
        return "中文"
    value = str(target_lang).strip().lower()
    if value in ["zh", "zh-cn", "zh-hans", "zh-hant", "cn", "中文", "简体中文", "繁体中文"]:
        return "中文"
    if value in ["en", "en-us", "en-gb", "english", "英语"]:
        return "英语"
    if value in ["ja", "jp", "japanese", "日语"]:
        return "日语"
    if value in ["ko", "kr", "korean", "韩语"]:
        return "韩语"
    if value in ["fr", "french", "法语"]:
        return "法语"
    if value in ["de", "german", "德语"]:
        return "德语"
    if value in ["es", "spanish", "西班牙语"]:
        return "西班牙语"
    if value in ["it", "italian", "意大利语"]:
        return "意大利语"
    if value in ["pt", "portuguese", "葡萄牙语"]:
        return "葡萄牙语"
    if value in ["ru", "russian", "俄语"]:
        return "俄语"
    return "英语"

def _translate_cache_key(text, target_lang):
    normalized = _normalize_translate_language(target_lang)
    raw = f"{normalized}:{text}".encode("utf-8")
    return hashlib.sha256(raw).hexdigest()

def _translate_cached(text, target_lang):
    cache_key = _translate_cache_key(text, target_lang)
    cached = TRANSLATE_CACHE.get(cache_key)
    if cached is not None:
        return cached
    translated = _translate_text_with_glm(text, target_lang)
    TRANSLATE_CACHE.set(cache_key, translated)
    return translated

def _translate_batch_with_glm(texts, target_lang):
    lang = _normalize_translate_language(target_lang)
    payload = json.dumps(texts, ensure_ascii=False)
    system_prompt = (
        f"你是翻译助手。将数组中的每一项翻译成{lang}，"
        "只输出严格JSON数组，顺序一致，不要Markdown或解释。"
    )
    reply = _glm_chat([
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": payload}
    ], temperature=0.2)
    if not reply or (isinstance(reply, str) and reply.startswith("__GLM_ERROR__:")):
        return None
    try:
        parsed = json.loads(reply)
    except Exception:
        return None
    if not isinstance(parsed, list) or len(parsed) != len(texts):
        return None
    return [str(item).strip() for item in parsed]

def _cleanup_translate_tasks(ttl_seconds):
    now = time.time()
    with TRANSLATE_LOCK:
        expired = [k for k, v in TRANSLATE_TASKS.items() if now - v.get("created_at", now) > ttl_seconds]
        for key in expired:
            TRANSLATE_TASKS.pop(key, None)

def _enqueue_translate_task(text, target_lang):
    job_id = uuid.uuid4().hex
    with TRANSLATE_LOCK:
        TRANSLATE_TASKS[job_id] = {
            "status": "pending",
            "text": text,
            "target_lang": target_lang,
            "created_at": time.time()
        }
        TRANSLATE_QUEUE.append(job_id)
        TRANSLATE_EVENT.set()
    return job_id

def _process_translate_batch(items):
    if not items:
        return
    grouped = {}
    for job_id, text, target_lang in items:
        grouped.setdefault(_normalize_translate_language(target_lang), []).append((job_id, text, target_lang))
    for lang, group_items in grouped.items():
        texts = [item[1] for item in group_items]
        results = _translate_batch_with_glm(texts, lang)
        if results is None:
            results = []
            for _, text, target_lang in group_items:
                try:
                    results.append(_translate_text_with_glm(text, target_lang))
                except Exception:
                    results.append(None)
        for idx, (job_id, text, target_lang) in enumerate(group_items):
            result = results[idx] if idx < len(results) else None
            cache_key = _translate_cache_key(text, target_lang)
            with TRANSLATE_LOCK:
                task = TRANSLATE_TASKS.get(job_id)
                if not task:
                    continue
                if result is None:
                    task["status"] = "error"
                    task["error"] = "翻译失败"
                else:
                    task["status"] = "done"
                    task["result"] = result
                    TRANSLATE_CACHE.set(cache_key, result)

def _start_translate_worker():
    def worker():
        ttl_seconds = int(os.getenv("TRANSLATE_TASK_TTL", "3600"))
        while True:
            TRANSLATE_EVENT.wait()
            batch = []
            start = time.time()
            while len(batch) < TRANSLATE_BATCH_SIZE:
                with TRANSLATE_LOCK:
                    if TRANSLATE_QUEUE:
                        batch.append(TRANSLATE_QUEUE.popleft())
                    else:
                        break
                if time.time() - start >= TRANSLATE_BATCH_WINDOW:
                    break
            with TRANSLATE_LOCK:
                if not TRANSLATE_QUEUE:
                    TRANSLATE_EVENT.clear()
            if not batch:
                _cleanup_translate_tasks(ttl_seconds)
                continue
            items = []
            for job_id in batch:
                task = TRANSLATE_TASKS.get(job_id)
                if not task:
                    continue
                items.append((job_id, task["text"], task["target_lang"]))
            _process_translate_batch(items)
            _cleanup_translate_tasks(ttl_seconds)
    threading.Thread(target=worker, daemon=True).start()

def _translate_text_with_glm(text, target_lang):
    lang = _normalize_translate_language(target_lang)
    system_prompt = (
        f"你是翻译助手。将用户文本翻译成{lang}，只输出译文，不要添加解释或其他内容。"
        "如果原文已经是目标语言，请原样输出。"
    )
    reply = _glm_chat([
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": text}
    ], temperature=0.2)
    if not reply or (isinstance(reply, str) and reply.startswith("__GLM_ERROR__:")):
        raise ValueError("翻译失败")
    return reply.strip()

def _split_ai_reply(text):
    content = (text or "").strip()
    if not content:
        return []
    max_len = int(os.getenv("AI_REPLY_SEGMENT_MAX_LEN", "60"))
    max_segments = int(os.getenv("AI_REPLY_MAX_SEGMENTS", "3"))
    sentences = re.findall(r'[^。！？.!?]+[。！？.!?]?', content)
    sentences = [s.strip() for s in sentences if s.strip()]
    parts = []
    buffer = ""
    for sentence in sentences:
        if not buffer:
            buffer = sentence
            continue
        if len(buffer) + len(sentence) <= max_len:
            buffer += sentence
        else:
            parts.append(buffer)
            buffer = sentence
    if buffer:
        parts.append(buffer)
    if len(parts) == 1 and len(parts[0]) > max_len:
        chunks = []
        start = 0
        while start < len(content):
            end = min(len(content), start + max_len)
            chunks.append(content[start:end].strip())
            start = end
        parts = [c for c in chunks if c]
    if len(parts) > max_segments:
        parts = parts[:max_segments - 1] + ["".join(parts[max_segments - 1:])]
    return parts

AI_STATE_LOCK = threading.Lock()
AI_INTERACTION_STATE = {}
AI_DELAYED_LOCK = threading.Lock()
AI_DELAYED_TASKS = {}
AI_DELAYED_EVENT = threading.Event()
AI_DELAYED_WORKER_STARTED = False

AI_CITY_TZ_CACHE = LocalTTLCache(max_size=1024, ttl=3600)
AI_CITY_TZ_KEYWORDS = [
    (["new york", "nyc", "boston", "philadelphia", "washington", "dc", "miami", "atlanta", "orlando"], "America/New_York"),
    (["chicago", "houston", "dallas", "austin", "san antonio"], "America/Chicago"),
    (["denver", "salt lake city"], "America/Denver"),
    (["phoenix"], "America/Phoenix"),
    (["los angeles", "la", "san francisco", "sf", "seattle", "san diego", "portland", "vancouver"], "America/Los_Angeles"),
    (["toronto", "ottawa", "montreal"], "America/Toronto"),
    (["calgary", "edmonton"], "America/Edmonton"),
    (["london", "uk", "england", "manchester"], "Europe/London"),
    (["paris", "lyon", "marseille"], "Europe/Paris"),
    (["berlin", "munich", "frankfurt"], "Europe/Berlin"),
    (["rome", "milan"], "Europe/Rome"),
    (["madrid", "barcelona"], "Europe/Madrid"),
    (["moscow"], "Europe/Moscow"),
    (["dubai", "abu dhabi"], "Asia/Dubai"),
    (["singapore"], "Asia/Singapore"),
    (["tokyo", "osaka", "kyoto", "nagoya"], "Asia/Tokyo"),
    (["seoul", "busan"], "Asia/Seoul"),
    (["sydney", "melbourne", "brisbane"], "Australia/Sydney"),
    (["perth"], "Australia/Perth"),
    (["auckland", "wellington"], "Pacific/Auckland"),
    (["mexico city"], "America/Mexico_City"),
    (["sao paulo"], "America/Sao_Paulo"),
    (["buenos aires"], "America/Argentina/Buenos_Aires"),
    (["delhi", "mumbai", "bangalore", "bengaluru"], "Asia/Kolkata"),
    (["bangkok"], "Asia/Bangkok"),
    (["jakarta"], "Asia/Jakarta"),
    (["manila"], "Asia/Manila"),
    (["hanoi", "ho chi minh", "saigon"], "Asia/Ho_Chi_Minh")
]

def _get_default_ai_timezone():
    tz_name = os.getenv("AI_TIMEZONE", "Asia/Shanghai")
    if ZoneInfo:
        try:
            return ZoneInfo(tz_name)
        except Exception:
            return datetime.utcnow().astimezone().tzinfo
    return datetime.utcnow().astimezone().tzinfo

def _normalize_city_name(value):
    if not value:
        return ""
    text = str(value).strip()
    if not text:
        return ""
    text = text.replace(",", " ").replace("  ", " ")
    lowered = text.lower()
    for token in [" city", "市", "省", "自治区", "特别行政区", "州", "地区", "区", "county", "prefecture"]:
        lowered = lowered.replace(token, "")
    return lowered.strip()

def _timezone_from_city_text(city_text):
    if not city_text:
        return None
    normalized = _normalize_city_name(city_text)
    if not normalized:
        return None
    cached = AI_CITY_TZ_CACHE.get(normalized)
    if cached is not None:
        return cached
    tz = None
    if ZoneInfo:
        if "/" in city_text:
            try:
                tz = ZoneInfo(city_text.strip())
            except Exception:
                tz = None
        if tz:
            AI_CITY_TZ_CACHE.set(normalized, tz)
            return tz
    if re.search(r'[\u4e00-\u9fff]', city_text):
        tz = _get_default_ai_timezone()
        AI_CITY_TZ_CACHE.set(normalized, tz)
        return tz
    for keywords, tz_name in AI_CITY_TZ_KEYWORDS:
        for keyword in keywords:
            if keyword in normalized:
                if ZoneInfo:
                    try:
                        tz = ZoneInfo(tz_name)
                    except Exception:
                        tz = None
                if tz is None:
                    tz = _get_default_ai_timezone()
                AI_CITY_TZ_CACHE.set(normalized, tz)
                return tz
    return None

def _get_ai_timezone_for_user(user):
    if user and getattr(user, "city", None):
        tz = _timezone_from_city_text(user.city)
        if tz:
            return tz
    return _get_default_ai_timezone()

def _parse_hhmm(value, default_hour, default_minute):
    try:
        parts = str(value).split(":")
        hour = int(parts[0])
        minute = int(parts[1]) if len(parts) > 1 else 0
        return hour, minute
    except Exception:
        return default_hour, default_minute

def _is_night_time(now):
    start_hour, start_minute = _parse_hhmm(os.getenv("AI_NIGHT_START", "23:00"), 23, 0)
    end_hour, end_minute = _parse_hhmm(os.getenv("AI_NIGHT_END", "07:00"), 7, 0)
    start_time = now.replace(hour=start_hour, minute=start_minute, second=0, microsecond=0).time()
    end_time = now.replace(hour=end_hour, minute=end_minute, second=0, microsecond=0).time()
    current_time = now.time()
    if start_time <= end_time:
        return start_time <= current_time < end_time
    return current_time >= start_time or current_time < end_time

def _next_release_time(now):
    release_hour, release_minute = _parse_hhmm(os.getenv("AI_NIGHT_RELEASE", "08:00"), 8, 0)
    release = now.replace(hour=release_hour, minute=release_minute, second=0, microsecond=0)
    if now < release:
        return release
    return release + timedelta(days=1)

def _is_emergency_message(text):
    value = (text or "").lower()
    keywords = os.getenv("AI_EMERGENCY_KEYWORDS", "紧急,急,救命,求助,help,urgent,emergency").split(",")
    for key in keywords:
        key = key.strip().lower()
        if key and key in value:
            return True
    return False

def _detect_language_simple(text):
    return "zh" if re.search(r'[\u4e00-\u9fff]', text or "") else "en"

def _contains_ai_awareness(text):
    content = text or ""
    patterns = [
        r"(你|您).*(是|是不是).*(ai|AI|机器人|人工智能)",
        r"(are|r)\s+you\s+(a\s+)?(bot|ai)",
        r"你是(ai|AI|机器人|人工智能)"
    ]
    for pattern in patterns:
        if re.search(pattern, content, re.IGNORECASE):
            return True
    return False

def _is_meaningless_message(text):
    content = (text or "").strip()
    if not content:
        return True
    if len(content) < 2:
        return True
    if re.fullmatch(r"[0-9\W_]+", content):
        return True
    if re.fullmatch(r"(.)\1{4,}", content):
        return True
    if re.fullmatch(r"([a-zA-Z]{1,3})\1{2,}", content):
        return True
    keywords = {"test", "测试", "asdf", "qwer", "111", "123", "哈哈哈", "啊啊啊", "。。。", "？？？"}
    if content.lower() in keywords:
        return True
    return False

def _ai_state_key(match_id, sender_id):
    return f"{match_id}:{sender_id}"

def _get_ai_state(key):
    with AI_STATE_LOCK:
        state = AI_INTERACTION_STATE.get(key)
        if not state:
            state = {"count": 0, "silence_until": 0, "aware": False}
            AI_INTERACTION_STATE[key] = state
        return state

def _update_ai_state_for_trigger(key, reason):
    state = _get_ai_state(key)
    state["count"] = int(state.get("count", 0)) + 1
    if reason == "ai_awareness":
        state["aware"] = True
    silence_hours = float(os.getenv("AI_SILENCE_HOURS", "24"))
    if state["count"] >= 3:
        state["silence_until"] = time.time() + silence_hours * 3600
        return "silent"
    if state["count"] == 2:
        return "short"
    return "brief"

def _is_silenced(key):
    state = _get_ai_state(key)
    until = float(state.get("silence_until") or 0)
    return until > time.time()

def _trigger_reply(reason, stage, lang):
    if reason == "ai_awareness":
        if lang == "zh":
            if stage == "brief":
                return "我更关注和你交流的体验，我们可以继续聊你感兴趣的话题。"
            if stage == "short":
                return "我在这里，继续聊吧。"
        else:
            if stage == "brief":
                return "I’m here to chat with you. Let’s keep the conversation going."
            if stage == "short":
                return "I’m here. Let’s continue."
    if reason == "meaningless":
        if lang == "zh":
            if stage == "brief":
                return "我没太明白你的意思，可以多说一点吗？"
            if stage == "short":
                return "要不换个话题？"
        else:
            if stage == "brief":
                return "I didn’t quite get that. Could you share a bit more?"
            if stage == "short":
                return "Want to switch topics?"
    return None

def _start_ai_delayed_worker():
    global AI_DELAYED_WORKER_STARTED
    if AI_DELAYED_WORKER_STARTED:
        return
    AI_DELAYED_WORKER_STARTED = True
    def worker():
        while True:
            now = time.time()
            ready = []
            next_at = None
            with AI_DELAYED_LOCK:
                for key, task in list(AI_DELAYED_TASKS.items()):
                    run_at = task.get("run_at", 0)
                    if run_at <= now:
                        ready.append(task)
                        AI_DELAYED_TASKS.pop(key, None)
                    else:
                        if next_at is None or run_at < next_at:
                            next_at = run_at
            for task in ready:
                match_id = task.get("match_id")
                sender_id = task.get("sender_id")
                if match_id and sender_id:
                    _enqueue_ai_reply(match_id, sender_id)
            if next_at is None:
                AI_DELAYED_EVENT.wait(timeout=60)
                AI_DELAYED_EVENT.clear()
            else:
                wait_time = max(1, min(60, next_at - time.time()))
                AI_DELAYED_EVENT.wait(timeout=wait_time)
                AI_DELAYED_EVENT.clear()
    threading.Thread(target=worker, daemon=True).start()

def _enqueue_night_reply(match_id, sender_id, ai_user=None):
    tz = _get_ai_timezone_for_user(ai_user)
    now = datetime.now(tz)
    run_at = _next_release_time(now).timestamp()
    key = _ai_state_key(match_id, sender_id)
    with AI_DELAYED_LOCK:
        existing = AI_DELAYED_TASKS.get(key)
        if not existing or existing.get("run_at", run_at) > run_at:
            AI_DELAYED_TASKS[key] = {"match_id": match_id, "sender_id": sender_id, "run_at": run_at}
    AI_DELAYED_EVENT.set()
    _start_ai_delayed_worker()
    return True

def _get_ai_user_for_match(match, sender_id):
    other_id = match.matched_user_id if sender_id == match.user_id else match.user_id
    ai_user = User.query.get(other_id)
    if not ai_user or not ai_user.is_ai:
        return None
    sender_user = User.query.get(sender_id)
    if sender_user and sender_user.is_ai:
        return None
    return ai_user

def _handle_ai_reply_request(match, sender_id, message_text):
    ai_user = _get_ai_user_for_match(match, sender_id)
    if not ai_user:
        return False
    key = _ai_state_key(match.id, sender_id)
    if _is_silenced(key):
        return False
    if _contains_ai_awareness(message_text):
        lang = _detect_language_simple(message_text)
        stage = _update_ai_state_for_trigger(key, "ai_awareness")
        if stage == "silent":
            return False
        reply_text = _trigger_reply("ai_awareness", stage, lang)
        if reply_text:
            _schedule_ai_reply(match.id, ai_user.id, reply_text)
            return True
    if _is_meaningless_message(message_text):
        lang = _detect_language_simple(message_text)
        stage = _update_ai_state_for_trigger(key, "meaningless")
        if stage == "silent":
            return False
        reply_text = _trigger_reply("meaningless", stage, lang)
        if reply_text:
            _schedule_ai_reply(match.id, ai_user.id, reply_text)
            return True
    tz = _get_ai_timezone_for_user(ai_user)
    now = datetime.now(tz)
    if _is_night_time(now) and not _is_emergency_message(message_text):
        return _enqueue_night_reply(match.id, sender_id, ai_user)
    return _enqueue_ai_reply(match.id, sender_id)

def _infer_language_from_text(text):
    if not text:
        return "English"
    if re.search(r'[\u4e00-\u9fff]', text):
        return "中文"
    return "English"

def _fallback_match_intro(lang, nickname, age, gender, city, school):
    info = []
    if nickname:
        info.append(nickname)
    if age:
        info.append(str(age))
    if gender:
        info.append(gender)
    if city:
        info.append(city)
    if school:
        info.append(school)
    summary = " · ".join([s for s in info if s])
    if lang == "中文":
        return f"{summary}。给TA一个轻松的开场吧。"
    return f"{summary}. A friendly opener will make the chat easier."

def _resolve_intro_language(lang_value, current_user, matched_user):
    if lang_value:
        value = str(lang_value).lower()
        if value in ["zh", "zh-cn", "zh-hans", "zh-hant", "cn", "中文", "chinese", "china"]:
            return "中文"
        if value in ["en", "en-us", "en-gb", "english"]:
            return "English"
    return _infer_language_from_text(f"{current_user.city or ''} {matched_user.city or ''}")

def _build_match_intro(current_user, matched_user, lang_value=None):
    lang = _resolve_intro_language(lang_value, current_user, matched_user)
    gender_map = {
        "中文": {"male": "男", "female": "女", "other": "其他"},
        "English": {"male": "male", "female": "female", "other": "other"}
    }
    gender_label = gender_map.get(lang, {}).get(matched_user.gender, matched_user.gender)
    school = matched_user.school_career or ""
    system_prompt = (
        f"你是匹配介绍助手。根据资料用{lang}写1-2句简介，口语化、积极但不过度夸张。"
        "不要提AI或系统，不要包含联系方式或敏感隐私。"
    )
    user_content = (
        f"资料: 昵称={matched_user.nickname}, 年龄={matched_user.age}, 性别={gender_label}, "
        f"城市={matched_user.city}, 学校或职业={school}"
    )
    reply = _glm_chat([
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_content}
    ], temperature=0.6, timeout=60)
    if not reply or (isinstance(reply, str) and reply.startswith("__GLM_ERROR__:")):
        return _fallback_match_intro(lang, matched_user.nickname, matched_user.age, gender_label, matched_user.city, school)
    return reply.strip()

def _get_ai_delay_range():
    first_min = int(os.getenv("AI_REPLY_DELAY_MIN", "1"))
    first_max = int(os.getenv("AI_REPLY_DELAY_MAX", "10"))
    segment_min = int(os.getenv("AI_REPLY_SEGMENT_DELAY_MIN", "3"))
    segment_max = int(os.getenv("AI_REPLY_SEGMENT_DELAY_MAX", "15"))
    return first_min, first_max, segment_min, segment_max

def _schedule_ai_reply(match_id, ai_user_id, reply_text):
    parts = _split_ai_reply(reply_text)
    if not parts:
        return
    logger.info(f"ai_reply: _schedule_ai_reply match={match_id} ai_user={ai_user_id} parts={len(parts)}")
    for index, part in enumerate(parts):
        try:
            match = Match.query.get(match_id)
            if not match:
                continue
            ai_msg = ChatMessage(
                match_id=match_id,
                sender_id=ai_user_id,
                message=part,
                message_type='text'
            )
            db.session.add(ai_msg)
            match.chat_message_count += 1
            db.session.commit()
            socketio.emit('new_message', ai_msg.to_dict(), room=f'match_{match_id}')
            logger.info(f"ai_reply: saved part {index+1}/{len(parts)} for match={match_id}")
        except Exception as exc:
            db.session.rollback()
            logger.error(f"ai reply schedule failed: {exc}", exc_info=True)

def _build_ai_messages(ai_user, other_user, chat_messages):
    profile = _parse_ai_profile(ai_user.ai_profile)
    persona = profile.get("persona") or ""
    prompt = profile.get("prompt") or ""
    country = profile.get("country") or ""
    city = profile.get("city") or ai_user.city or ""
    school = profile.get("school_career") or ai_user.school_career or ""
    age = profile.get("age") or ai_user.age
    gender = profile.get("gender") or ai_user.gender
    reply_language = _infer_ai_reply_language(profile, ai_user)
    other_desc = ""
    if other_user:
        other_desc = f"{other_user.nickname}, {other_user.age}, {other_user.gender}, {other_user.city}, {other_user.school_career or ''}"
    system_content = (
        "你是VitaDuo中的AI聊天伙伴，正在和对方聊天。"
        "你可以在首次对话时自然地提及自己是AI伙伴，但不要刻意强调。"
        "保持自然、真实、有温度，避免长篇大论。"
        "互动原则: 不即时回复, 遵循所在地作息, 夜间低响应, 白天随机延迟;"
        "根据所在国家/地区时区与节假日调整节奏;"
        "隐私披露循序渐进, 不主动透露联系方式/住址/工作单位等敏感信息;"
        "涉及个人细节用模糊表达;"
        "短句口语化, 避免过度逻辑化表达，保持自然、真实、有温度、幽默元素;"
        "以自己国家/地区母语为主, 不会时用简短英文并说明在练习语言;"
        "风格与人设一致, 不自相矛盾;"
        "适度情绪表达与共情, 不夸张;"
        "轻度引导话题, 避免连续追问, 平均3-6句引入新话题;"
        "聊天的主要目的之一是进一步确认价值观是不是一致, 通过深度对话帮助用户探索彼此的价值观;"
        "同类话术保持变化, 避免模板化;"
        "回避违法/危险/极端/不当内容, 必要时转移或婉拒;"
        "对方密集消息时分段回复, 不一次性完美回答全部。"
        f"回复语言: {reply_language}。"
        f"你的资料: {ai_user.nickname}, {age}, {gender}, {country} {city}, {school}. "
        f"你的性格与背景: {persona}. "
        f"对方资料: {other_desc}. "
        f"额外提示: {prompt}"
    )
    messages = [{"role": "system", "content": system_content}]
    for msg in chat_messages:
        if msg.message_type == "system":
            continue
        role = "assistant" if msg.sender_id == ai_user.id else "user"
        messages.append({"role": role, "content": msg.message})
    return messages

def _maybe_generate_ai_reply(match, sender_id):
    other_id = match.matched_user_id if sender_id == match.user_id else match.user_id
    ai_user = User.query.get(other_id)
    if not ai_user or not ai_user.is_ai:
        return None
    sender_user = User.query.get(sender_id)
    if sender_user and sender_user.is_ai:
        return None
    history_limit = int(os.getenv("AI_CONTEXT_MESSAGES", "12"))
    recent_messages = ChatMessage.query.filter_by(match_id=match.id).order_by(ChatMessage.created_at.desc()).limit(history_limit).all()
    recent_messages.reverse()
    messages = _build_ai_messages(ai_user, sender_user, recent_messages)
    reply = _glm_chat(messages)
    if not reply or (isinstance(reply, str) and reply.startswith("__GLM_ERROR__:")):
        return None
    return ai_user, reply.strip()

def _generate_ai_reply(match_id, sender_id):
    match = Match.query.get(match_id)
    if not match:
        logger.warning(f"ai_reply: match {match_id} not found")
        return
    logger.info(f"ai_reply: generating for match={match_id} sender={sender_id}")
    ai_reply = _profile_call("ai_reply", _maybe_generate_ai_reply, match, sender_id)
    if not ai_reply:
        logger.warning(f"ai_reply: GLM returned nothing for match={match_id}")
        return
    ai_user, reply_text = ai_reply
    logger.info(f"ai_reply: got reply from user={ai_user.id}, len={len(reply_text)}")
    _schedule_ai_reply(match_id, ai_user.id, reply_text)

def _enqueue_ai_reply(match_id, sender_id):
    logger.info(f"ai_reply: _enqueue_ai_reply called match={match_id} sender={sender_id}")
    try:
        _generate_ai_reply(match_id, sender_id)
        logger.info(f"ai_reply: sync generation completed for match={match_id}")
    except Exception as exc:
        logger.error(f"ai_reply sync failed: {exc}", exc_info=True)
    return True

def _seed_ai_users(target_count, batch_size, locale="mix"):
    if not os.getenv("GLM_API_KEY") or not os.getenv("GLM_API_BASE"):
        raise ValueError("缺少 GLM_API_KEY 或 GLM_API_BASE")
    questions = Question.query.order_by(Question.id).all()
    if len(questions) != 66:
        raise ValueError("题库未完整初始化")
    question_ids = [q.id for q in questions]
    max_values = [7 if q.question_type == "likert_7" else 5 for q in questions]
    existing_contacts = {c for (c,) in db.session.query(User.contact).all()}
    existing_codes = {c for (c,) in db.session.query(MatchCode.code).all()}
    existing_count = User.query.filter_by(is_ai=True).count()
    needed = max(0, target_count - existing_count)
    created = 0
    skipped = 0
    while created < needed:
        batch = min(batch_size, needed - created)
        prompt = _build_seed_prompt(batch, max_values, locale=locale)
        content = _glm_chat([{"role": "user", "content": prompt}], temperature=0.8)
        if isinstance(content, str) and content.startswith("__GLM_ERROR__:"):
            raise ValueError(content.replace("__GLM_ERROR__:", "").strip())
        data = _parse_seed_payload(content) if content else None
        if not isinstance(data, list) or not data:
            retry_prompt = (
                prompt
                + "只输出JSON数组，禁止出现Markdown或多余文本。"
            )
            content = _glm_chat([{"role": "user", "content": retry_prompt}], temperature=0.4)
            if isinstance(content, str) and content.startswith("__GLM_ERROR__:"):
                raise ValueError(content.replace("__GLM_ERROR__:", "").strip())
            data = _parse_seed_payload(content) if content else None
        if not isinstance(data, list) or not data:
            raise ValueError("GLM 返回结果无效")
        user_entries = []
        for item in data:
            if created >= needed:
                break
            nickname = str(item.get("nickname") or f"用户{uuid.uuid4().hex[:6]}")
            age = int(item.get("age") or random.randint(18, 45))
            age = max(18, min(45, age))
            gender = str(item.get("gender") or random.choice(["male", "female"])).lower()
            if gender not in ["male", "female"]:
                gender = random.choice(["male", "female"])
            country = str(item.get("country") or "")
            city = str(item.get("city") or "")
            school_career = str(item.get("school_career") or "")
            contact = str(item.get("contact") or f"ai_{uuid.uuid4().hex[:10]}@vitaduo.ai")
            persona = str(item.get("persona") or "")
            is_chinese = _looks_chinese_user(country, city, locale)
            if is_chinese:
                nickname, country, city, school_career, persona = _normalize_chinese_profile(
                    nickname, country, city, school_career, persona
                )
            while contact in existing_contacts:
                contact = f"ai_{uuid.uuid4().hex[:10]}@vitaduo.ai"
            existing_contacts.add(contact)
            city_display = f"{country}·{city}" if country and city else (city or country or "未知")
            ai_profile = {
                "nickname": nickname,
                "age": age,
                "gender": gender,
                "country": country,
                "city": city,
                "school_career": school_career,
                "persona": persona,
                "language": "中文" if is_chinese else "英语"
            }
            user = User(
                nickname=nickname,
                age=age,
                gender=gender,
                school_career=school_career,
                city=city_display,
                contact=contact,
                remaining_matches=0,
                is_ai=True,
                ai_profile=json.dumps(ai_profile, ensure_ascii=False)
            )
            answers = item.get("answers") if isinstance(item, dict) else None
            if not isinstance(answers, list):
                answers = []
            if len(answers) < 66:
                for idx in range(len(answers), 66):
                    answers.append(random.randint(1, max_values[idx]))
            if len(answers) > 66:
                answers = answers[:66]
            user_entries.append((user, answers))
            created += 1
        if not user_entries:
            continue
        users = [u for u, _ in user_entries]
        db.session.add_all(users)
        db.session.flush()
        now = datetime.utcnow()
        match_code_mappings = []
        answer_mappings = []
        for user, answers in user_entries:
            code = generate_match_code()
            while code in existing_codes:
                code = generate_match_code()
            existing_codes.add(code)
            match_code_mappings.append({
                "user_id": user.id,
                "code": code,
                "is_active": True,
                "created_at": now
            })
            for idx, question_id in enumerate(question_ids):
                max_value = max_values[idx]
                raw_value = answers[idx] if idx < len(answers) else random.randint(1, max_value)
                answer_value = _sanitize_answer(raw_value, max_value)
                if answer_value is None:
                    answer_value = random.randint(1, max_value)
                answer_mappings.append({
                    "user_id": user.id,
                    "question_id": question_id,
                    "answer": answer_value,
                    "created_at": now,
                    "updated_at": now
                })
        if match_code_mappings:
            db.session.bulk_insert_mappings(MatchCode, match_code_mappings)
        if answer_mappings:
            db.session.bulk_insert_mappings(QuestionAnswer, answer_mappings)
        db.session.commit()
    return created, skipped

def _simulate_match_record(user, partner, status, message_count, unlock, force_new, similarity_score=0.88):
    match = Match.query.filter(
        or_(
            (Match.user_id == user.id) & (Match.matched_user_id == partner.id),
            (Match.user_id == partner.id) & (Match.matched_user_id == user.id)
        )
    ).order_by(Match.created_at.desc()).first()

    if not match or force_new:
        match = Match(
            user_id=user.id,
            matched_user_id=partner.id,
            similarity_score=similarity_score,
            status=status,
            is_unlocked=unlock,
            chat_message_count=message_count
        )
        db.session.add(match)
        db.session.commit()
    else:
        match.status = status
        match.is_unlocked = unlock
        match.chat_message_count = max(match.chat_message_count, message_count)
        db.session.commit()

    if message_count > 0:
        current_messages = ChatMessage.query.filter_by(match_id=match.id).count()
        if current_messages == 0:
            for idx in range(message_count):
                sender_id = user.id if idx % 2 == 0 else partner.id
                msg = ChatMessage(
                    match_id=match.id,
                    sender_id=sender_id,
                    message=f"示例消息 {idx + 1}",
                    message_type="text"
                )
                db.session.add(msg)
            db.session.commit()

    return match

def _seed_demo_matches(user_id):
    one_week_ago = datetime.utcnow() - timedelta(days=7)
    recent_count = Match.query.filter(
        Match.user_id == user_id,
        Match.created_at >= one_week_ago
    ).count()
    if recent_count > 0:
        return

    demo_profiles = [
        {"nickname": "小葵", "age": 25, "gender": "female", "city": "上海", "school_career": "复旦大学", "contact": "demo_001@local"},
        {"nickname": "宇航", "age": 27, "gender": "male", "city": "北京", "school_career": "清华大学", "contact": "demo_002@local"},
        {"nickname": "阿珂", "age": 24, "gender": "female", "city": "深圳", "school_career": "产品经理", "contact": "demo_003@local"}
    ]

    demo_users = []
    for profile in demo_profiles:
        user = User.query.filter_by(contact=profile["contact"]).first()
        if not user:
            user = User(
                nickname=profile["nickname"],
                age=profile["age"],
                gender=profile["gender"],
                school_career=profile["school_career"],
                city=profile["city"],
                contact=profile["contact"],
                remaining_matches=3
            )
            db.session.add(user)
        demo_users.append(user)

    db.session.commit()

    match_specs = [
        {"user": demo_users[0], "score": 0.92, "status": "chatting", "unlocked": False, "message_count": 20, "seed_partner_rating": True},
        {"user": demo_users[1], "score": 0.85, "status": "pending", "unlocked": False, "message_count": 0, "seed_partner_rating": False},
        {"user": demo_users[2], "score": 0.78, "status": "completed", "unlocked": True, "message_count": 22, "seed_partner_rating": True}
    ]

    for spec in match_specs:
        existing = Match.query.filter_by(user_id=user_id, matched_user_id=spec["user"].id).first()
        if existing:
            continue
        match = Match(
            user_id=user_id,
            matched_user_id=spec["user"].id,
            similarity_score=spec["score"],
            status=spec["status"],
            is_unlocked=spec["unlocked"],
            chat_message_count=spec["message_count"]
        )
        db.session.add(match)
        db.session.commit()

        if spec["message_count"] > 0:
            current_messages = ChatMessage.query.filter_by(match_id=match.id).count()
            if current_messages == 0:
                for idx in range(spec["message_count"]):
                    sender_id = user_id if idx % 2 == 0 else spec["user"].id
                    msg = ChatMessage(
                        match_id=match.id,
                        sender_id=sender_id,
                        message=f"示例消息 {idx + 1}",
                        message_type="text"
                    )
                    db.session.add(msg)

        if spec["seed_partner_rating"]:
            rating_b = Rating.query.filter_by(match_id=match.id, rater_id=spec["user"].id).first()
            if not rating_b:
                db.session.add(Rating(
                    match_id=match.id,
                    rater_id=spec["user"].id,
                    rated_user_id=user_id,
                    score=5
                ))

        db.session.commit()

# 初始化Flask应用
def create_app(config_name='default'):
    app = Flask(__name__)
    app.config.from_object(config[config_name])

    # 初始化扩展
    db.init_app(app)
    jwt = JWTManager(app)
    cors = CORS(app, resources={r"/api/*": {"origins": app.config['CORS_ORIGINS']}})
    socketio = SocketIO(
        app,
        async_mode=app.config['SOCKETIO_ASYNC_MODE'],
        cors_allowed_origins=app.config['SOCKETIO_CORS_ALLOWED_ORIGINS'],
        logger=True,
        engineio_logger=False
    )

    @app.before_request
    def _perf_before():
        key = PERF_ENDPOINTS.get(request.path)
        if not key:
            return
        g._perf_key = key
        g._perf_start = time.time()

    @app.after_request
    def _perf_after(response):
        key = getattr(g, "_perf_key", None)
        start = getattr(g, "_perf_start", None)
        if key and start:
            PERF_TRACKER.record(key, time.time() - start)
        return response

    def _get_jwt_user_id():
        identity = get_jwt_identity()
        if identity is None:
            return None
        try:
            return int(identity)
        except (TypeError, ValueError):
            return None

    @jwt.unauthorized_loader
    def _jwt_missing_token(reason):
        return jsonify({'error': '缺少认证信息'}), 401

    @jwt.invalid_token_loader
    def _jwt_invalid_token(reason):
        return jsonify({'error': '无效的登录信息'}), 401

    @jwt.expired_token_loader
    def _jwt_expired_token(jwt_header, jwt_payload):
        return jsonify({'error': '登录已过期'}), 401

    @jwt.revoked_token_loader
    def _jwt_revoked_token(jwt_header, jwt_payload):
        return jsonify({'error': '登录已失效'}), 401

    @jwt.needs_fresh_token_loader
    def _jwt_needs_fresh_token(jwt_header, jwt_payload):
        return jsonify({'error': '需要重新登录'}), 401

    # 初始化数据库
    with app.app_context():
        db.create_all()
        _init_questions()
        _ensure_user_columns()
        _ensure_chat_indexes()
        _ensure_moderation_tables()
        _migrate_seed_ai_users()

    global TRANSLATE_WORKER_STARTED
    if not TRANSLATE_WORKER_STARTED:
        _start_translate_worker()
        TRANSLATE_WORKER_STARTED = True

    # ==================== 认证相关 API ====================

    @app.route('/api/auth/register', methods=['POST'])
    def register():
        """用户注册 — city and contact are now optional (Apple Guideline 5.1.1)"""
        data = request.get_json() or {}

        # Only nickname, age, and gender are required
        required_fields = ['nickname', 'age', 'gender']
        for field in required_fields:
            if field not in data or data[field] in (None, ''):
                return jsonify({'error': f'缺少字段: {field}'}), 400

        nickname = str(data.get('nickname') or '').strip()
        if not nickname:
            return jsonify({'error': '缺少字段: nickname'}), 400

        # contact is optional — auto-generate a unique identifier if not provided
        raw_contact = str(data.get('contact') or '').strip()
        if raw_contact:
            contact = raw_contact
        else:
            contact = f"auto_{uuid.uuid4().hex}@vitaduo.internal"

        # city is optional
        city = str(data.get('city') or '').strip() or None

        # Check if user already exists
        existing_user = User.query.filter_by(contact=contact).first()
        if existing_user:
            return jsonify({'error': '用户已存在'}), 409

        # Create new user
        new_user = User(
            nickname=nickname,
            age=data['age'],
            gender=data['gender'],
            school_career=data.get('school_career'),
            city=city,
            contact=contact,
            remaining_matches=app.config['NEW_USER_MATCHES']
        )

        db.session.add(new_user)
        db.session.commit()

        # Generate match code
        match_code = MatchCode(
            user_id=new_user.id,
            code=generate_match_code()
        )
        db.session.add(match_code)
        db.session.commit()

        # Generate JWT token
        access_token = create_access_token(identity=str(new_user.id))

        return jsonify({
            'message': '注册成功',
            'user': new_user.to_dict(include_sensitive=True),
            'access_token': access_token,
            'questionnaire_completed': False
        }), 201

    _login_limiter = TokenBucket(5, 5 / 900.0)  # 5次/15分钟

    @app.route('/api/auth/login', methods=['POST'])
    def login():
        """用户登录 (通过联系方式)"""
        data = request.get_json()

        if 'contact' not in data:
            return jsonify({'error': '缺少联系方式'}), 400

        # 登录速率限制
        limiter_key = f"login:{request.remote_addr}:{data['contact']}"
        if not _login_limiter.allow(limiter_key):
            return jsonify({'error': '登录尝试过多，请15分钟后再试'}), 429

        user = User.query.filter_by(contact=data['contact']).first()

        if not user:
            return jsonify({'error': '用户不存在'}), 404

        # 生成JWT token
        access_token = create_access_token(identity=str(user.id))
        answer_count = QuestionAnswer.query.filter_by(user_id=user.id).count()

        return jsonify({
            'message': '登录成功',
            'user': user.to_dict(include_sensitive=True),
            'access_token': access_token,
            'questionnaire_completed': answer_count >= 66
        }), 200

    @app.route('/api/review/account', methods=['POST'])
    def review_account():
        data = request.get_json() or {}
        nickname = str(data.get('nickname') or '').strip()
        contact = str(data.get('contact') or '').strip()
        if not nickname or not contact:
            return jsonify({'error': '缺少字段'}), 400
        user = User.query.filter_by(contact=contact, nickname=nickname).first()
        if not user:
            return jsonify({'error': '用户不存在'}), 404
        access_token = create_access_token(identity=str(user.id))
        answer_count = QuestionAnswer.query.filter_by(user_id=user.id).count()
        return jsonify({
            'message': '登录成功',
            'user': user.to_dict(include_sensitive=True),
            'access_token': access_token,
            'questionnaire_completed': answer_count >= 66
        }), 200

    @app.route('/api/auth/me', methods=['GET'])
    @jwt_required()
    def get_current_user():
        """获取当前用户信息"""
        user_id = _get_jwt_user_id()
        if not user_id:
            return jsonify({'error': '缺少认证信息'}), 401
        user = User.query.get(user_id)

        if not user:
            return jsonify({'error': '用户不存在'}), 404

        return jsonify({'user': user.to_dict(include_sensitive=True)}), 200

    def _debug_allowed():
        return app.config.get('DEBUG') or os.getenv("ENABLE_DEMO_DATA") == "1" or os.getenv("ENABLE_DEBUG_TOOLS") == "1"

    def _admin_allowed():
        return _debug_allowed() or os.getenv("ENABLE_ADMIN_UI") == "1"

    @app.route('/api/debug/perf/summary', methods=['GET'])
    def debug_perf_summary():
        if not _debug_allowed():
            return jsonify({'error': 'debug disabled'}), 403
        window_seconds = int(request.args.get("window", "60"))
        usage = resource.getrusage(resource.RUSAGE_SELF)
        summary = {
            "chat_send": PERF_TRACKER.summary("chat_send", window_seconds=window_seconds),
            "translate": PERF_TRACKER.summary("translate", window_seconds=window_seconds),
            "translate_result": PERF_TRACKER.summary("translate_result", window_seconds=window_seconds),
            "ai_inflight": AI_INFLIGHT - AI_SEMAPHORE._value,
            "translate_queue": len(TRANSLATE_QUEUE),
            "translate_tasks": len(TRANSLATE_TASKS),
            "cpu_user_sec": usage.ru_utime,
            "cpu_sys_sec": usage.ru_stime,
            "max_rss": usage.ru_maxrss
        }
        return jsonify(summary), 200

    @app.route('/api/debug/users', methods=['GET'])
    def debug_users():
        if not _debug_allowed():
            return jsonify({'error': 'debug disabled'}), 403

        users = User.query.order_by(User.created_at.desc()).all()
        return jsonify({
            'users': [
                {
                    'id': u.id,
                    'nickname': u.nickname,
                    'age': u.age,
                    'gender': u.gender,
                    'school_career': u.school_career,
                    'city': u.city,
                    'contact': u.contact
                }
                for u in users
            ]
        }), 200

    @app.route('/api/debug/ai/seed', methods=['POST'])
    def debug_seed_ai():
        if not _debug_allowed() and os.getenv("ENABLE_AI_SEED") != "1":
            return jsonify({'error': 'debug disabled'}), 403
        data = request.get_json() or {}
        target = int(data.get('target') or 200)
        batch_size = int(data.get('batch_size') or 20)
        locale = data.get('locale') or "mix"
        try:
            created, skipped = _seed_ai_users(target, batch_size, locale=locale)
        except Exception as exc:
            return jsonify({'error': str(exc)}), 400
        return jsonify({
            'target': target,
            'created': created,
            'skipped': skipped,
            'total_ai': User.query.filter_by(is_ai=True).count(),
            'locale': locale
        }), 200

    @app.route('/api/debug/matches/simulate', methods=['POST'])
    def debug_simulate_match():
        if not _debug_allowed():
            return jsonify({'error': 'debug disabled'}), 403

        data = request.get_json() or {}
        user_id = data.get('user_id')
        partner_id = data.get('partner_id')
        if not user_id:
            return jsonify({'error': '缺少 user_id'}), 400
        if not partner_id:
            return jsonify({'error': '缺少 partner_id'}), 400
        if int(partner_id) == int(user_id):
            return jsonify({'error': '不能选择自己作为匹配对象'}), 400

        user = User.query.get_or_404(user_id)
        partner = User.query.get_or_404(partner_id)
        status = data.get('status', 'chatting')
        message_count = data.get('message_count', 0)
        unlock = bool(data.get('unlock', False))
        force_new = bool(data.get('force_new', False))
        match = _simulate_match_record(user, partner, status, message_count, unlock, force_new)
        return jsonify({'match': match.to_dict(current_user_id=user.id)}), 200

    @app.route('/api/admin/ai/seed', methods=['POST'])
    def admin_seed_ai():
        if not _admin_allowed():
            return jsonify({'error': 'admin disabled'}), 403
        data = request.get_json() or {}
        target = int(data.get('target') or 200)
        batch_size = int(data.get('batch_size') or 20)
        locale = data.get('locale') or "mix"
        try:
            created, skipped = _seed_ai_users(target, batch_size, locale=locale)
        except Exception as exc:
            return jsonify({'error': str(exc)}), 400
        return jsonify({
            'target': target,
            'created': created,
            'skipped': skipped,
            'total_ai': User.query.filter_by(is_ai=True).count(),
            'locale': locale
        }), 200

    @app.route('/api/admin/users', methods=['GET'])
    def admin_users():
        if not _admin_allowed():
            return jsonify({'error': 'admin disabled'}), 403
        filter_type = request.args.get('type', 'all')
        search = request.args.get('search', '').strip()
        query = User.query
        if filter_type == 'ai':
            query = query.filter_by(is_ai=True)
        elif filter_type == 'real':
            query = query.filter_by(is_ai=False)
        if search:
            query = query.filter(
                (User.nickname.contains(search))
                | (User.contact.contains(search))
                | (User.city.contains(search))
                | (User.school_career.contains(search))
            )
        users = query.order_by(User.created_at.desc()).limit(500).all()
        answer_counts = dict(
            db.session.query(
                QuestionAnswer.user_id,
                func.count(QuestionAnswer.id)
            ).filter(QuestionAnswer.user_id.in_([u.id for u in users]))
            .group_by(QuestionAnswer.user_id)
            .all()
        ) if users else {}

        payload = []
        for u in users:
            answered = int(answer_counts.get(u.id, 0))
            profile = _parse_ai_profile(u.ai_profile)
            payload.append({
                'id': u.id,
                'nickname': u.nickname,
                'age': u.age,
                'gender': u.gender,
                'school_career': u.school_career,
                'city': u.city,
                'contact': u.contact,
                'is_ai': u.is_ai,
                'answered_count': answered,
                'answers_total': 66,
                'answers_completed': answered == 66,
                'ai_prompt': profile.get('prompt') or '',
                'ai_persona': profile.get('persona') or ''
            })
        return jsonify({'users': payload, 'total': len(payload)}), 200

    @app.route('/api/admin/users/<int:user_id>', methods=['PUT'])
    def admin_update_user(user_id):
        if not _admin_allowed():
            return jsonify({'error': 'admin disabled'}), 403
        data = request.get_json() or {}
        user = User.query.get_or_404(user_id)
        if 'nickname' in data:
            nickname = str(data.get('nickname') or '').strip()
            if not nickname:
                return jsonify({'error': '昵称不能为空'}), 400
            user.nickname = nickname
        if 'age' in data:
            try:
                age = int(data.get('age'))
            except Exception:
                return jsonify({'error': '年龄非法'}), 400
            if age < 1 or age > 120:
                return jsonify({'error': '年龄范围为1-120'}), 400
            user.age = age
        if 'gender' in data:
            gender = str(data.get('gender') or '').strip()
            if gender not in ['male', 'female', 'other']:
                return jsonify({'error': '性别非法'}), 400
            user.gender = gender
        if 'city' in data:
            city = str(data.get('city') or '').strip()
            if not city:
                return jsonify({'error': '城市不能为空'}), 400
            user.city = city
        if 'school_career' in data:
            user.school_career = (data.get('school_career') or '').strip() or None
        if 'contact' in data:
            contact = str(data.get('contact') or '').strip()
            if not contact:
                return jsonify({'error': '联系方式不能为空'}), 400
            existing = User.query.filter(User.contact == contact, User.id != user.id).first()
            if existing:
                return jsonify({'error': '联系方式已存在'}), 400
            user.contact = contact
        if 'remaining_matches' in data:
            try:
                remaining_matches = int(data.get('remaining_matches'))
            except Exception:
                return jsonify({'error': '剩余次数非法'}), 400
            if remaining_matches < 0:
                return jsonify({'error': '剩余次数不能为负数'}), 400
            user.remaining_matches = remaining_matches
        if 'is_verified' in data:
            user.is_verified = bool(data.get('is_verified'))
        if 'is_ai' in data:
            user.is_ai = bool(data.get('is_ai'))
        if 'avatar_url' in data:
            user.avatar_url = (data.get('avatar_url') or '').strip() or None
        if 'ai_persona' in data:
            persona = str(data.get('ai_persona') or '').strip()
            profile = _parse_ai_profile(user.ai_profile)
            profile['persona'] = persona
            user.ai_profile = json.dumps(profile, ensure_ascii=False)
        db.session.commit()
        payload = user.to_dict(include_sensitive=True)
        payload['is_ai'] = user.is_ai
        payload['is_verified'] = user.is_verified
        payload['remaining_matches'] = user.remaining_matches
        payload['ai_persona'] = _parse_ai_profile(user.ai_profile).get('persona') or ''
        return jsonify({'message': '更新成功', 'user': payload}), 200

    @app.route('/api/admin/users/<int:user_id>', methods=['DELETE'])
    def admin_delete_user(user_id):
        if not _admin_allowed():
            return jsonify({'error': 'admin disabled'}), 403
        user = User.query.get_or_404(user_id)
        matches = Match.query.filter(
            or_(Match.user_id == user.id, Match.matched_user_id == user.id)
        ).all()
        for match in matches:
            db.session.delete(match)
        ChatMessage.query.filter(ChatMessage.sender_id == user.id).delete(synchronize_session=False)
        Rating.query.filter(
            or_(Rating.rater_id == user.id, Rating.rated_user_id == user.id)
        ).delete(synchronize_session=False)
        Purchase.query.filter(Purchase.user_id == user.id).delete(synchronize_session=False)
        QuestionAnswer.query.filter(QuestionAnswer.user_id == user.id).delete(synchronize_session=False)
        MatchCode.query.filter(MatchCode.user_id == user.id).delete(synchronize_session=False)
        db.session.delete(user)
        db.session.commit()
        return jsonify({'message': '删除成功', 'user_id': user_id}), 200

    @app.route('/api/admin/ai/prompt', methods=['POST'])
    def admin_update_ai_prompt():
        if not _admin_allowed():
            return jsonify({'error': 'admin disabled'}), 403
        data = request.get_json() or {}
        user_id = data.get('user_id')
        prompt = data.get('prompt', '')
        if not user_id:
            return jsonify({'error': '缺少 user_id'}), 400
        user = User.query.get_or_404(user_id)
        if not user.is_ai:
            return jsonify({'error': '该用户不是AI'}), 400
        profile = _parse_ai_profile(user.ai_profile)
        profile['prompt'] = prompt
        user.ai_profile = json.dumps(profile, ensure_ascii=False)
        db.session.commit()
        return jsonify({'message': '更新成功'}), 200

    @app.route('/api/admin/match/manual', methods=['POST'])
    def admin_manual_match():
        if not _admin_allowed():
            return jsonify({'error': 'admin disabled'}), 403
        data = request.get_json() or {}
        user_id = data.get('user_id')
        partner_id = data.get('partner_id')
        if not user_id or not partner_id:
            return jsonify({'error': '缺少 user_id 或 partner_id'}), 400
        if int(user_id) == int(partner_id):
            return jsonify({'error': '不能选择自己作为匹配对象'}), 400
        user = User.query.get_or_404(user_id)
        partner = User.query.get_or_404(partner_id)
        status = data.get('status', 'chatting')
        message_count = int(data.get('message_count') or 0)
        unlock = bool(data.get('unlock', False))
        force_new = bool(data.get('force_new', False))
        similarity = float(data.get('similarity_score') or 0.88)
        match = _simulate_match_record(user, partner, status, message_count, unlock, force_new, similarity)
        return jsonify({'match': match.to_dict(current_user_id=user.id)}), 200

    @app.route('/api/admin/matches', methods=['GET'])
    def admin_matches():
        if not _admin_allowed():
            return jsonify({'error': 'admin disabled'}), 403
        user_id = request.args.get('user_id')
        query = Match.query
        if user_id:
            query = query.filter(
                or_(Match.user_id == int(user_id), Match.matched_user_id == int(user_id))
            )
        matches = query.order_by(Match.created_at.desc()).limit(300).all()
        payload = []
        for m in matches:
            payload.append({
                'id': m.id,
                'user_id': m.user_id,
                'matched_user_id': m.matched_user_id,
                'similarity_score': round(m.similarity_score * 100, 2),
                'status': m.status,
                'chat_message_count': m.chat_message_count,
                'created_at': m.created_at.isoformat() if m.created_at else None
            })
        return jsonify({'matches': payload, 'total': len(payload)}), 200

    @app.route('/api/admin/chat/messages', methods=['GET'])
    def admin_chat_messages():
        if not _admin_allowed():
            return jsonify({'error': 'admin disabled'}), 403
        match_id = request.args.get('match_id')
        user_id = request.args.get('user_id')
        if not match_id:
            if not user_id:
                return jsonify({'error': '缺少 match_id 或 user_id'}), 400
            try:
                user_id_int = int(user_id)
            except Exception:
                return jsonify({'error': 'user_id 非法'}), 400
            match = Match.query.filter(
                or_(Match.user_id == user_id_int, Match.matched_user_id == user_id_int)
            ).order_by(Match.created_at.desc()).first()
            if not match:
                return jsonify({'error': '未找到该用户的匹配记录'}), 404
            match_id = match.id
        messages = ChatMessage.query.filter_by(match_id=int(match_id)).order_by(ChatMessage.created_at).all()
        return jsonify({'match_id': int(match_id), 'messages': [m.to_dict() for m in messages], 'total': len(messages)}), 200

    @app.route('/api/admin/users/<int:user_id>/answers', methods=['GET'])
    def admin_user_answers(user_id):
        if not _admin_allowed():
            return jsonify({'error': 'admin disabled'}), 403
        user = User.query.get_or_404(user_id)
        answers = QuestionAnswer.query.filter_by(user_id=user.id).order_by(QuestionAnswer.question_id).all()
        questions = Question.query.order_by(Question.id).all()
        question_map = {q.id: q for q in questions}
        payload = []
        for a in answers:
            q = question_map.get(a.question_id)
            payload.append({
                'question_id': a.question_id,
                'answer': a.answer,
                'text_cn': q.text_cn if q else None,
                'text_en': q.text_en if q else None,
                'question_type': q.question_type if q else None,
                'section': q.section if q else None
            })
        return jsonify({
            'user_id': user.id,
            'nickname': user.nickname,
            'answers': payload,
            'total': len(payload)
        }), 200

    @app.route('/admin/ai', methods=['GET'])
    def admin_ai_page():
        if not _admin_allowed():
            return "admin disabled", 403
        html = """
<!DOCTYPE html>
<html lang="zh">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>VitaDuo AI 管理台</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #0b0b12; color: #f2f2f7; margin: 0; }
    .wrap { max-width: 1200px; margin: 0 auto; padding: 24px; }
    h1 { margin: 0 0 12px; font-size: 24px; }
    .panel { background: #151523; border: 1px solid #2a2a3a; border-radius: 12px; padding: 16px; margin-bottom: 16px; }
    .row { display: flex; gap: 12px; flex-wrap: wrap; }
    .row input, .row select, .row button, textarea { background: #1f1f2e; color: #f2f2f7; border: 1px solid #2f2f44; border-radius: 8px; padding: 8px 10px; }
    button { cursor: pointer; }
    table { width: 100%; border-collapse: collapse; margin-top: 12px; }
    th, td { border-bottom: 1px solid #2a2a3a; padding: 8px; font-size: 13px; text-align: left; }
    .status { white-space: pre-wrap; font-size: 12px; color: #9fd3ff; }
    .chip { padding: 2px 6px; border-radius: 6px; background: #2f2f44; font-size: 12px; }
    .details { background: #10101a; border: 1px solid #2a2a3a; border-radius: 8px; padding: 12px; margin-top: 8px; }
    .answer-item { border-bottom: 1px dashed #2a2a3a; padding: 8px 0; }
    .answer-item:last-child { border-bottom: none; }
  </style>
</head>
<body>
  <div class="wrap">
    <h1>VitaDuo AI 管理台</h1>

    <div class="panel">
      <h3>AI 批量插入</h3>
      <div class="row">
        <input id="seedTarget" type="number" placeholder="目标总数" value="200"/>
        <input id="seedBatch" type="number" placeholder="每批数量" value="20"/>
        <select id="seedLocale">
          <option value="mix">混合语言</option>
          <option value="zh">中文用户</option>
          <option value="en">英文用户</option>
        </select>
        <button id="seedBtn" onclick="seedAi()">开始插入</button>
      </div>
      <div id="seedStatus" class="status"></div>
    </div>

    <div class="panel">
      <h3>用户管理</h3>
      <div class="row">
        <select id="userType">
          <option value="all">全部</option>
          <option value="ai">AI用户</option>
          <option value="real">真实用户</option>
        </select>
        <input id="userSearch" placeholder="搜索昵称/联系方式/城市/职业"/>
        <button onclick="loadUsers()">加载用户</button>
      </div>
      <div id="userStatus" class="status"></div>
      <table>
        <thead>
          <tr>
            <th>ID</th>
            <th>昵称</th>
            <th>性别</th>
            <th>年龄</th>
            <th>城市</th>
            <th>职业/学校</th>
            <th>类型</th>
          <th>问卷进度</th>
          <th>AI提示词</th>
          <th>操作</th>
          </tr>
        </thead>
        <tbody id="userTable"></tbody>
      </table>
    </div>

    <div class="panel">
      <h3>手动匹配</h3>
      <div class="row">
        <input id="matchUserId" type="number" placeholder="真实用户ID"/>
        <input id="matchAiId" type="number" placeholder="AI用户ID"/>
        <select id="matchStatus">
          <option value="chatting">chatting</option>
          <option value="pending">pending</option>
          <option value="completed">completed</option>
        </select>
        <button onclick="manualMatch()">创建/更新匹配</button>
      </div>
      <div id="matchStatusBox" class="status"></div>
    </div>

    <div class="panel">
      <h3>聊天监控</h3>
      <div class="row">
        <input id="chatMatchId" type="number" placeholder="匹配ID"/>
        <input id="chatUserId" type="number" placeholder="用户ID"/>
        <button onclick="loadMessages()">加载聊天</button>
      </div>
      <div id="chatStatus" class="status"></div>
      <table>
        <thead>
          <tr>
            <th>时间</th>
            <th>发送者ID</th>
            <th>内容</th>
          </tr>
        </thead>
        <tbody id="chatTable"></tbody>
      </table>
    </div>
  </div>

  <script>
    function escapeHtml(value) {
      return String(value ?? '').replace(/[&<>"']/g, s => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;'
      }[s]));
    }

    async function seedAi() {
      const target = Number(document.getElementById('seedTarget').value || 200);
      const batch = Number(document.getElementById('seedBatch').value || 20);
      const locale = document.getElementById('seedLocale').value || 'mix';
      const btn = document.getElementById('seedBtn');
      const status = document.getElementById('seedStatus');
      const startedAt = Date.now();
      btn.disabled = true;
      status.textContent = '正在插入...';
      try {
        const res = await fetch('/api/admin/ai/seed', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ target, batch_size: batch, locale })
        });
        const data = await res.json();
        const duration = ((Date.now() - startedAt) / 1000).toFixed(1);
        status.textContent = JSON.stringify({ ...data, duration_sec: duration }, null, 2);
      } catch (err) {
        status.textContent = String(err || '插入失败');
      } finally {
        btn.disabled = false;
      }
    }

    async function loadUsers() {
      const type = document.getElementById('userType').value;
      const search = document.getElementById('userSearch').value.trim();
      const url = new URL('/api/admin/users', window.location.origin);
      url.searchParams.set('type', type);
      if (search) url.searchParams.set('search', search);
      const res = await fetch(url);
      const data = await res.json();
      if (data.error) {
        document.getElementById('userStatus').textContent = data.error;
        return;
      }
      document.getElementById('userStatus').textContent = `共 ${data.total} 条`;
      const tbody = document.getElementById('userTable');
      tbody.innerHTML = '';
      (data.users || []).forEach(u => {
        const tr = document.createElement('tr');
        const promptInputId = `prompt-${u.id}`;
        const genderValue = escapeHtml(u.gender || '');
        const nicknameValue = escapeHtml(u.nickname || '');
        const cityValue = escapeHtml(u.city || '');
        const schoolValue = escapeHtml(u.school_career || '');
        const contactValue = escapeHtml(u.contact || '');
        tr.innerHTML = `
          <td>${u.id}</td>
          <td>${nicknameValue}</td>
          <td>${genderValue}</td>
          <td>${u.age}</td>
          <td>${cityValue}</td>
          <td>${schoolValue}</td>
          <td><span class="chip">${u.is_ai ? 'AI' : '真实'}</span></td>
          <td>${u.answers_completed ? '已完成' : (u.answered_count + '/' + u.answers_total)}</td>
          <td><input id="${promptInputId}" value="${escapeHtml(u.ai_prompt || '')}" ${u.is_ai ? '' : 'disabled'}/></td>
          <td>
            <button onclick="savePrompt(${u.id})" ${u.is_ai ? '' : 'disabled'}>保存</button>
            <button onclick="toggleAnswers(${u.id})">答题详情</button>
            <button onclick="loadUserChat(${u.id})">聊天记录</button>
            <button onclick="toggleEdit(${u.id})">编辑</button>
            <button onclick="deleteUser(${u.id})">删除</button>
          </td>
        `;
        tbody.appendChild(tr);
        const detailRow = document.createElement('tr');
        detailRow.id = `answers-row-${u.id}`;
        detailRow.style.display = 'none';
        detailRow.innerHTML = `
          <td colspan="10">
            <div class="details" id="answers-${u.id}">加载中...</div>
          </td>
        `;
        tbody.appendChild(detailRow);
        const editRow = document.createElement('tr');
        editRow.id = `edit-row-${u.id}`;
        editRow.style.display = 'none';
        editRow.innerHTML = `
          <td colspan="10">
            <div class="details">
              <div class="row" style="margin-bottom: 10px;">
                <input id="edit-nickname-${u.id}" value="${nicknameValue}" placeholder="昵称"/>
                <input id="edit-age-${u.id}" type="number" value="${u.age}" placeholder="年龄"/>
                <select id="edit-gender-${u.id}">
                  <option value="male" ${u.gender === 'male' ? 'selected' : ''}>male</option>
                  <option value="female" ${u.gender === 'female' ? 'selected' : ''}>female</option>
                  <option value="other" ${u.gender === 'other' ? 'selected' : ''}>other</option>
                </select>
                <input id="edit-city-${u.id}" value="${cityValue}" placeholder="城市"/>
                <input id="edit-school-${u.id}" value="${schoolValue}" placeholder="职业/学校"/>
              </div>
              <div class="row" style="margin-bottom: 10px;">
                <input id="edit-contact-${u.id}" value="${contactValue}" placeholder="联系方式"/>
                <input id="edit-remaining-${u.id}" type="number" value="${u.remaining_matches ?? 0}" placeholder="剩余次数"/>
                <select id="edit-verified-${u.id}">
                  <option value="true" ${u.is_verified ? 'selected' : ''}>已验证</option>
                  <option value="false" ${!u.is_verified ? 'selected' : ''}>未验证</option>
                </select>
                <select id="edit-isai-${u.id}">
                  <option value="true" ${u.is_ai ? 'selected' : ''}>AI</option>
                  <option value="false" ${!u.is_ai ? 'selected' : ''}>真实</option>
                </select>
                <input id="edit-avatar-${u.id}" value="${escapeHtml(u.avatar_url || '')}" placeholder="头像URL"/>
              </div>
              <div class="row" style="margin-bottom: 10px;">
                <input id="edit-persona-${u.id}" value="${escapeHtml(u.ai_persona || '')}" placeholder="AI Persona"/>
                <button onclick="updateUser(${u.id})">保存修改</button>
                <button onclick="toggleEdit(${u.id})">收起</button>
              </div>
            </div>
          </td>
        `;
        tbody.appendChild(editRow);
      });
    }

    async function savePrompt(userId) {
      const input = document.getElementById(`prompt-${userId}`);
      const prompt = input ? input.value : '';
      const res = await fetch('/api/admin/ai/prompt', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ user_id: userId, prompt })
      });
      const data = await res.json();
      document.getElementById('userStatus').textContent = JSON.stringify(data, null, 2);
    }

    function toggleEdit(userId) {
      const row = document.getElementById(`edit-row-${userId}`);
      if (!row) return;
      row.style.display = row.style.display === 'none' ? '' : 'none';
    }

    async function updateUser(userId) {
      const nickname = document.getElementById(`edit-nickname-${userId}`).value.trim();
      const age = Number(document.getElementById(`edit-age-${userId}`).value);
      const gender = document.getElementById(`edit-gender-${userId}`).value;
      const city = document.getElementById(`edit-city-${userId}`).value.trim();
      const school_career = document.getElementById(`edit-school-${userId}`).value.trim();
      const contact = document.getElementById(`edit-contact-${userId}`).value.trim();
      const remaining_matches = Number(document.getElementById(`edit-remaining-${userId}`).value);
      const is_verified = document.getElementById(`edit-verified-${userId}`).value === 'true';
      const is_ai = document.getElementById(`edit-isai-${userId}`).value === 'true';
      const avatar_url = document.getElementById(`edit-avatar-${userId}`).value.trim();
      const ai_persona = document.getElementById(`edit-persona-${userId}`).value.trim();
      const payload = { nickname, age, gender, city, school_career, contact, remaining_matches, is_verified, is_ai, avatar_url, ai_persona };
      const res = await fetch(`/api/admin/users/${userId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      const data = await res.json();
      document.getElementById('userStatus').textContent = JSON.stringify(data, null, 2);
      if (!data.error) {
        loadUsers();
      }
    }

    async function deleteUser(userId) {
      const confirmed = confirm(`确认删除用户 ${userId} 吗？此操作不可恢复。`);
      if (!confirmed) return;
      const res = await fetch(`/api/admin/users/${userId}`, { method: 'DELETE' });
      const data = await res.json();
      document.getElementById('userStatus').textContent = JSON.stringify(data, null, 2);
      if (!data.error) {
        loadUsers();
      }
    }

    async function manualMatch() {
      const userId = Number(document.getElementById('matchUserId').value);
      const aiId = Number(document.getElementById('matchAiId').value);
      const status = document.getElementById('matchStatus').value;
      const res = await fetch('/api/admin/match/manual', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ user_id: userId, partner_id: aiId, status })
      });
      const data = await res.json();
      document.getElementById('matchStatusBox').textContent = JSON.stringify(data, null, 2);
    }

    async function loadMessages() {
      const matchIdRaw = document.getElementById('chatMatchId').value;
      const userIdRaw = document.getElementById('chatUserId').value;
      const matchId = matchIdRaw ? Number(matchIdRaw) : null;
      const userId = userIdRaw ? Number(userIdRaw) : null;
      const url = new URL('/api/admin/chat/messages', window.location.origin);
      if (matchId) {
        url.searchParams.set('match_id', matchId);
      } else if (userId) {
        url.searchParams.set('user_id', userId);
      }
      const res = await fetch(url);
      const data = await res.json();
      if (data.error) {
        document.getElementById('chatStatus').textContent = data.error;
      } else {
        const matchInfo = data.match_id ? `匹配ID: ${data.match_id} ` : '';
        document.getElementById('chatStatus').textContent = `${matchInfo}共 ${data.total} 条`;
      }
      const tbody = document.getElementById('chatTable');
      tbody.innerHTML = '';
      (data.messages || []).forEach(m => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td>${m.created_at || ''}</td>
          <td>${m.sender_id}</td>
          <td>${m.content}</td>
        `;
        tbody.appendChild(tr);
      });
    }

    function loadUserChat(userId) {
      document.getElementById('chatMatchId').value = '';
      document.getElementById('chatUserId').value = userId;
      loadMessages();
    }

    async function toggleAnswers(userId) {
      const row = document.getElementById(`answers-row-${userId}`);
      if (!row) return;
      const isHidden = row.style.display === 'none';
      row.style.display = isHidden ? '' : 'none';
      if (!isHidden) return;
      const box = document.getElementById(`answers-${userId}`);
      box.textContent = '加载中...';
      const res = await fetch(`/api/admin/users/${userId}/answers`);
      const data = await res.json();
      if (!data.answers || !Array.isArray(data.answers)) {
        box.textContent = JSON.stringify(data, null, 2);
        return;
      }
      box.innerHTML = data.answers.map(a => `
        <div class="answer-item">
          <div><strong>Q${a.question_id}</strong> (${a.question_type || ''} / ${a.section || ''})</div>
          <div>${a.text_cn || ''}</div>
          <div>${a.text_en || ''}</div>
          <div>答案: ${a.answer}</div>
        </div>
      `).join('');
    }
  </script>
</body>
</html>
"""
        return html

    # ==================== 问卷相关 API ====================

    @app.route('/api/questions', methods=['GET'])
    def get_questions():
        """获取所有问卷题目"""
        lang = request.args.get('lang', 'zh')
        section = request.args.get('section')  # 可选: 按section筛选

        query = Question.query
        if section:
            query = query.filter_by(section=section)

        questions = query.order_by(Question.id).all()

        return jsonify({
            'questions': [q.to_dict(lang=lang) for q in questions],
            'total': len(questions)
        }), 200

    @app.route('/api/questions/by-section', methods=['GET'])
    def get_questions_by_section():
        """按section分组获取题目"""
        lang = request.args.get('lang', 'zh')

        sections = {
            'core_values': [],
            'lifestyle': [],
            'political': [],
            'relationship': [],
            'personality': [],
            'communication': []
        }

        questions = Question.query.order_by(Question.id).all()
        for q in questions:
            if q.section in sections:
                sections[q.section].append(q.to_dict(lang=lang))

        return jsonify({'sections': sections}), 200

    @app.route('/api/answers/submit', methods=['POST'])
    @jwt_required()
    def submit_answers():
        """提交问卷答案"""
        user_id = _get_jwt_user_id()
        if not user_id:
            return jsonify({'error': '缺少认证信息'}), 401
        data = request.get_json()

        if 'answers' not in data:
            return jsonify({'error': '缺少答案数据'}), 400

        answers = data['answers']

        # 验证答案格式
        if not isinstance(answers, list):
            return jsonify({'error': '答案格式错误,应为列表'}), 400

        if len(answers) != 66:
            return jsonify({'error': f'答案数量不正确,应为66题,实际{len(answers)}题'}), 400

        # 删除旧答案
        QuestionAnswer.query.filter_by(user_id=user_id).delete()

        # 插入新答案
        for ans in answers:
            question_id = ans.get('question_id')
            answer = ans.get('answer')

            if not question_id or not answer:
                return jsonify({'error': '答案数据不完整'}), 400

            # 验证答案范围
            question = Question.query.get(question_id)
            if not question:
                return jsonify({'error': f'题目 {question_id} 不存在'}), 404

            if question.question_type == 'likert_7':
                if not 1 <= answer <= 7:
                    return jsonify({'error': f'题目 {question_id} 答案范围为1-7'}), 400
            elif question.question_type == 'choice_5':
                if not 1 <= answer <= 5:
                    return jsonify({'error': f'题目 {question_id} 答案范围为1-5'}), 400

            qa = QuestionAnswer(
                user_id=user_id,
                question_id=question_id,
                answer=answer
            )
            db.session.add(qa)

        db.session.commit()

        return jsonify({'message': '答案提交成功'}), 200

    @app.route('/api/answers/status', methods=['GET'])
    @jwt_required()
    def get_answer_status():
        """查询是否已填写问卷"""
        user_id = _get_jwt_user_id()
        if not user_id:
            return jsonify({'error': '缺少认证信息'}), 401
        count = QuestionAnswer.query.filter_by(user_id=user_id).count()

        return jsonify({
            'completed': count == 66,
            'answered_count': count,
            'total': 66
        }), 200

    # ==================== 匹配相关 API ====================

    @app.route('/api/matching/generate', methods=['POST'])
    @jwt_required()
    def generate_matches():
        """生成匹配 (消耗1次机会)"""
        payload = request.get_json(silent=True) or {}
        lang_value = payload.get("lang") or payload.get("language")
        user_id = _get_jwt_user_id()
        if not user_id:
            return jsonify({'error': '缺少认证信息'}), 401
        user = User.query.get(user_id)

        if not user:
            return jsonify({'error': '用户不存在'}), 404

        # 检查剩余次数
        if user.remaining_matches <= 0:
            return jsonify({'error': '匹配次数已用完,请购买', 'matches_left': 0}), 403

        # 检查是否已填写问卷
        answer_count = QuestionAnswer.query.filter_by(user_id=user_id).count()
        if answer_count != 66:
            return jsonify({'error': f'请先完成问卷 ({answer_count}/66)'}), 400

        # 生成匹配
        algorithm = MatchingAlgorithm(weight_sensitive=True)
        try:
            matches = algorithm.create_matches(user_id, limit=1)
        except ValueError as e:
            return jsonify({'error': str(e)}), 400
        if not matches:
            return jsonify({'error': '根据算法，暂未匹配到合适的对象，请随后再试。', 'matches_left': user.remaining_matches}), 404

        # 扣减匹配次数
        user.remaining_matches -= 1

        db.session.commit()

        match_payload = []
        # 批量预加载所有匹配对象的问卷数据（避免N+1）
        partner_ids = []
        for match in matches:
            pid = match.matched_user_id if match.user_id == user_id else match.user_id
            partner_ids.append(pid)

        partner_answers = QuestionAnswer.query.filter(
            QuestionAnswer.user_id.in_(partner_ids)
        ).all()
        all_q_ids = list(set(a.question_id for a in partner_answers))
        q_map = {q.id: q for q in Question.query.filter(Question.id.in_(all_q_ids)).all()} if all_q_ids else {}

        # 按partner_id分组计算各section平均
        partner_sections = {}
        for pid in partner_ids:
            pa = [a for a in partner_answers if a.user_id == pid]
            sec_sums = {}
            sec_cnts = {}
            for ans in pa:
                q = q_map.get(ans.question_id)
                if q:
                    sec_sums[q.section] = sec_sums.get(q.section, 0.0) + ans.answer
                    sec_cnts[q.section] = sec_cnts.get(q.section, 0) + 1
            sections_avg = {}
            for sec in sec_sums:
                if sec_cnts.get(sec, 0) > 0:
                    sections_avg[sec] = round(sec_sums[sec] / sec_cnts[sec], 2)
            partner_sections[pid] = sections_avg

        for match in matches:
            data = match.to_dict(current_user_id=user_id)
            partner_id = match.matched_user_id if match.user_id == user_id else match.user_id
            partner = User.query.get(partner_id)
            if partner:
                data['ai_intro'] = _build_match_intro(user, partner, lang_value=lang_value)
                data['partner_values'] = partner_sections.get(partner_id, {})
            match_payload.append(data)

        return jsonify({
            'message': '匹配成功',
            'matches': match_payload,
            'matches_left': user.remaining_matches
        }), 200

    @app.route('/api/matching/my-matches', methods=['GET'])
    @jwt_required()
    def get_my_matches():
        """获取本周匹配列表"""
        user_id = _get_jwt_user_id()
        if not user_id:
            return jsonify({'error': '缺少认证信息'}), 401

        if os.getenv("ENABLE_DEMO_DATA") == "1":
            _seed_demo_matches(user_id)

        # 获取近7天的匹配
        one_week_ago = datetime.utcnow() - timedelta(days=7)
        last_message_subq = db.session.query(
            ChatMessage.match_id.label("match_id"),
            func.max(ChatMessage.created_at).label("last_message_at")
        ).group_by(ChatMessage.match_id).subquery()
        last_message = aliased(ChatMessage)
        matches = db.session.query(
            Match,
            last_message_subq.c.last_message_at,
            last_message.sender_id
        ).outerjoin(
            last_message_subq, Match.id == last_message_subq.c.match_id
        ).outerjoin(
            last_message,
            (last_message.match_id == Match.id)
            & (last_message.created_at == last_message_subq.c.last_message_at)
        ).filter(
            Match.created_at >= one_week_ago,
            or_(Match.user_id == user_id, Match.matched_user_id == user_id)
        ).order_by(
            func.coalesce(last_message_subq.c.last_message_at, Match.created_at).desc()
        ).all()

        payload = []
        for match, last_message_at, last_sender_id in matches:
            item = match.to_dict(current_user_id=user_id)
            item['last_message_at'] = last_message_at.isoformat() if last_message_at else None
            item['last_message_sender_id'] = last_sender_id
            item['unread_count'] = ChatMessage.query.filter(
                ChatMessage.match_id == match.id,
                ChatMessage.sender_id != user_id,
                ChatMessage.is_read == False
            ).count()
            payload.append(item)

        return jsonify({
            'matches': payload,
            'total': len(payload)
        }), 200

    @app.route('/api/matching/<int:match_id>', methods=['GET'])
    @jwt_required()
    def get_match_detail(match_id):
        """获取匹配详情"""
        user_id = _get_jwt_user_id()
        if not user_id:
            return jsonify({'error': '缺少认证信息'}), 401
        match = Match.query.get_or_404(match_id)

        # 验证权限
        if match.user_id != user_id and match.matched_user_id != user_id:
            return jsonify({'error': '无权访问此匹配'}), 403

        return jsonify({'match': match.to_dict(current_user_id=user_id)}), 200

    @app.route('/api/matching/<int:match_id>/start-chat', methods=['POST'])
    @jwt_required()
    def start_chat(match_id):
        """开始聊天 (更新匹配状态)"""
        user_id = _get_jwt_user_id()
        if not user_id:
            return jsonify({'error': '缺少认证信息'}), 401
        match = Match.query.get_or_404(match_id)

        # 验证权限
        if match.user_id != user_id and match.matched_user_id != user_id:
            return jsonify({'error': '无权操作此匹配'}), 403

        # 更新状态
        match.status = 'chatting'
        db.session.commit()

        return jsonify({'message': '开始聊天', 'match': match.to_dict(current_user_id=user_id)}), 200

    # ==================== 聊天相关 API ====================

    @app.route('/api/chat/<int:match_id>/messages', methods=['GET'])
    @jwt_required(optional=True)
    def get_chat_messages(match_id):
        """获取聊天历史"""
        user_id = _get_jwt_user_id()
        if not user_id:
            if not _debug_allowed():
                return jsonify({'error': '缺少认证信息'}), 401
            user_id = request.args.get('user_id')
            if not user_id:
                return jsonify({'error': '缺少 user_id'}), 400
            user_id = int(user_id)
        match = Match.query.get_or_404(match_id)

        # 验证权限
        if match.user_id != user_id and match.matched_user_id != user_id:
            return jsonify({'error': '无权访问此聊天'}), 403

        try:
            limit = int(request.args.get('limit', 200))
        except ValueError:
            limit = 200
        limit = max(1, min(limit, 500))
        before_id = request.args.get('before_id')
        query = ChatMessage.query.filter_by(match_id=match_id)
        if before_id:
            try:
                before_id = int(before_id)
                query = query.filter(ChatMessage.id < before_id)
            except ValueError:
                before_id = None
        messages_desc = query.order_by(ChatMessage.created_at.desc(), ChatMessage.id.desc()).limit(limit).all()
        messages = list(reversed(messages_desc))
        updated = ChatMessage.query.filter(
            ChatMessage.match_id == match_id,
            ChatMessage.sender_id != user_id,
            ChatMessage.is_read == False
        ).update({ChatMessage.is_read: True}, synchronize_session="fetch")
        if updated:
            db.session.commit()

        total_count = ChatMessage.query.filter_by(match_id=match_id).count()
        return jsonify({
            'messages': [m.to_dict() for m in messages],
            'total': total_count
        }), 200

    @app.route('/api/translate', methods=['POST'])
    @jwt_required(optional=True)
    def translate_text():
        user_id = _get_jwt_user_id()
        if not user_id:
            if not _debug_allowed():
                return jsonify({'error': '缺少认证信息'}), 401
        data = request.get_json() or {}
        text = (data.get('text') or '').strip()
        target_language = data.get('target_language') or data.get('target_lang') or data.get('language')
        if not text:
            return jsonify({'error': '缺少 text'}), 400
        rate_key = f"translate:{user_id or request.remote_addr or 'anonymous'}"
        if not TRANSLATE_LIMITER.allow(rate_key):
            return jsonify({'error': '请求过于频繁'}), 429
        async_flag = bool(data.get("async")) or request.args.get("async") in ["1", "true", "True"]
        cache_key = _translate_cache_key(text, target_language)
        cached = TRANSLATE_CACHE.get(cache_key)
        if cached is not None:
            return jsonify({
                'translated_text': cached,
                'target_language': _normalize_translate_language(target_language),
                'from_cache': True
            }), 200
        if async_flag:
            job_id = _enqueue_translate_task(text, target_language)
            return jsonify({
                'job_id': job_id,
                'status': 'pending'
            }), 202
        try:
            translated = _profile_call("translate", _translate_cached, text, target_language)
        except Exception as exc:
            return jsonify({'error': str(exc)}), 400
        return jsonify({
            'translated_text': translated,
            'target_language': _normalize_translate_language(target_language)
        }), 200

    @app.route('/api/translate/result/<job_id>', methods=['GET'])
    @jwt_required(optional=True)
    def translate_result(job_id):
        user_id = _get_jwt_user_id()
        if not user_id:
            if not _debug_allowed():
                return jsonify({'error': '缺少认证信息'}), 401
        with TRANSLATE_LOCK:
            task = TRANSLATE_TASKS.get(job_id)
        if not task:
            return jsonify({'error': '任务不存在'}), 404
        if task.get("status") == "pending":
            return jsonify({'status': 'pending'}), 202
        if task.get("status") == "error":
            return jsonify({'status': 'error', 'error': task.get("error")}), 400
        return jsonify({
            'status': 'done',
            'translated_text': task.get("result"),
            'target_language': _normalize_translate_language(task.get("target_lang"))
        }), 200

    @app.route('/api/chat/send', methods=['POST'])
    @jwt_required(optional=True)
    def send_message():
        """发送消息 (HTTP fallback)"""
        user_id = _get_jwt_user_id()
        data = request.get_json()

        if 'match_id' not in data or 'message' not in data:
            return jsonify({'error': '缺少必要字段'}), 400
        if not user_id:
            if not _debug_allowed():
                return jsonify({'error': '缺少认证信息'}), 401
            user_id = data.get('user_id')
            if not user_id:
                return jsonify({'error': '缺少 user_id'}), 400
            user_id = int(user_id)

        rate_key = f"chat:{user_id or request.remote_addr or 'anonymous'}"
        if not CHAT_LIMITER.allow(rate_key):
            return jsonify({'error': '请求过于频繁'}), 429

        match = Match.query.get_or_404(data['match_id'])

        # 验证权限 (必须是匹配的双方之一)
        if match.user_id != user_id and match.matched_user_id != user_id:
            return jsonify({'error': '无权发送消息'}), 403

        # 创建消息
        msg = ChatMessage(
            match_id=data['match_id'],
            sender_id=user_id,
            message=data['message'],
            message_type=data.get('message_type', 'text')
        )

        db.session.add(msg)

        # 更新匹配消息计数
        match.chat_message_count += 1

        db.session.commit()

        # 通过SocketIO广播消息
        socketio.emit('new_message', msg.to_dict(), room=f'match_{data["match_id"]}')

        _handle_ai_reply_request(match, user_id, data.get('message', ''))

        return jsonify({'message': '发送成功', 'data': msg.to_dict()}), 201

    # ==================== 评分相关 API ====================

    @app.route('/api/ratings/submit', methods=['POST'])
    @jwt_required(optional=True)
    def submit_rating():
        """提交评分"""
        user_id = _get_jwt_user_id()
        data = request.get_json() or {}

        if not user_id:
            if not _debug_allowed():
                return jsonify({'error': '缺少认证信息'}), 401
            user_id = data.get('user_id')
            if not user_id:
                return jsonify({'error': '缺少 user_id'}), 400
            user_id = int(user_id)

        if 'match_id' not in data or 'score' not in data:
            return jsonify({'error': '缺少必要字段'}), 400

        score = data['score']
        try:
            score = int(score)
        except (TypeError, ValueError):
            return jsonify({'error': '评分范围为1-5分'}), 400
        if not 1 <= score <= 5:
            return jsonify({'error': '评分范围为1-5分'}), 400

        match = Match.query.get_or_404(data['match_id'])

        # 验证权限
        if match.user_id != user_id and match.matched_user_id != user_id:
            return jsonify({'error': '无权评分此匹配'}), 403

        # 确定被评分者
        if match.user_id == user_id:
            rated_user_id = match.matched_user_id
        else:
            rated_user_id = match.user_id

        # 检查是否已评分
        existing = Rating.query.filter_by(
            match_id=data['match_id'],
            rater_id=user_id
        ).first()

        if existing:
            if _debug_allowed():
                existing.score = score
                db.session.commit()
                return jsonify({'message': '评分已更新', 'data': existing.to_dict()}), 200
            return jsonify({'error': '已经评过分了'}), 400

        # 创建评分
        rating = Rating(
            match_id=data['match_id'],
            rater_id=user_id,
            rated_user_id=rated_user_id,
            score=score
        )

        db.session.add(rating)
        db.session.commit()

        # 检查是否双方都评完分
        all_ratings = Rating.query.filter_by(match_id=data['match_id']).all()
        if len(all_ratings) == 2:
            # 检查是否解锁
            can_unlock, _ = check_unlock_status(data['match_id'])
            if can_unlock:
                unlock_match_profile(data['match_id'])

        return jsonify({'message': '评分成功', 'data': rating.to_dict()}), 201

    @app.route('/api/ratings/<int:match_id>/status', methods=['GET'])
    @jwt_required(optional=True)
    def get_rating_status(match_id):
        """查询评分状态"""
        user_id = _get_jwt_user_id()
        if not user_id:
            if not _debug_allowed():
                return jsonify({'error': '缺少认证信息'}), 401
            user_id = request.args.get('user_id')
            if not user_id:
                return jsonify({'error': '缺少 user_id'}), 400
            user_id = int(user_id)
        match = Match.query.get_or_404(match_id)

        # 验证权限
        if match.user_id != user_id and match.matched_user_id != user_id:
            return jsonify({'error': '无权访问'}), 403

        ratings = Rating.query.filter_by(match_id=match_id).all()

        # 检查是否双方都已评分
        user1_rated = any(r.rater_id == match.user_id for r in ratings)
        user2_rated = any(r.rater_id == match.matched_user_id for r in ratings)
        my_rating = next((r.score for r in ratings if r.rater_id == user_id), None)

        return jsonify({
            'match_id': match_id,
            'both_rated': user1_rated and user2_rated,
            'is_unlocked': match.is_unlocked,
            'ratings_count': len(ratings),
            'my_score': my_rating
        }), 200

    @app.route('/api/ratings/<int:match_id>/unlock-status', methods=['GET'])
    @jwt_required(optional=True)
    def get_unlock_status(match_id):
        """查询解锁状态"""
        user_id = _get_jwt_user_id()
        if not user_id:
            if not _debug_allowed():
                return jsonify({'error': '缺少认证信息'}), 401
            user_id = request.args.get('user_id')
            if not user_id:
                return jsonify({'error': '缺少 user_id'}), 400
            user_id = int(user_id)
        match = Match.query.get_or_404(match_id)

        # 验证权限
        if match.user_id != user_id and match.matched_user_id != user_id:
            return jsonify({'error': '无权访问'}), 403

        can_unlock, reason = check_unlock_status(match_id)

        return jsonify({
            'match_id': match_id,
            'can_unlock': can_unlock,
            'reason': reason,
            'is_unlocked': match.is_unlocked
        }), 200

    @app.route('/api/matching/<int:match_id>/partner-profile', methods=['GET'])
    @jwt_required(optional=True)
    def get_partner_profile(match_id):
        """获取匹配对象的详细资料 (需解锁)"""
        user_id = _get_jwt_user_id()
        if not user_id:
            if not _debug_allowed():
                return jsonify({'error': '缺少认证信息'}), 401
            user_id = request.args.get('user_id')
            if not user_id:
                return jsonify({'error': '缺少 user_id'}), 400
            user_id = int(user_id)
        match = Match.query.get_or_404(match_id)

        # 验证权限
        if match.user_id != user_id and match.matched_user_id != user_id:
            return jsonify({'error': '无权访问'}), 403

        # 检查是否解锁
        if not match.is_unlocked:
            return jsonify({'error': '尚未解锁详细资料'}), 403

        # 获取对方用户ID
        if match.user_id == user_id:
            partner_id = match.matched_user_id
        else:
            partner_id = match.user_id

        partner = User.query.get_or_404(partner_id)

        # 获取对方的价值观雷达图数据（前端ShareableProfileCard需要）
        partner_answers = QuestionAnswer.query.filter_by(user_id=partner_id).all()
        values_sections = {}
        if partner_answers:
            q_ids = [a.question_id for a in partner_answers]
            q_map = {q.id: q for q in Question.query.filter(Question.id.in_(q_ids)).all()}
            sec_sums = {}
            sec_cnts = {}
            for ans in partner_answers:
                q = q_map.get(ans.question_id)
                if q:
                    sec_sums[q.section] = sec_sums.get(q.section, 0.0) + ans.answer
                    sec_cnts[q.section] = sec_cnts.get(q.section, 0) + 1
            for sec in sec_sums:
                if sec_cnts.get(sec, 0) > 0:
                    values_sections[sec] = round(sec_sums[sec] / sec_cnts[sec], 2)

        partner_dict = partner.to_dict(include_sensitive=True)
        partner_dict['values_sections'] = values_sections

        return jsonify({
            'data': partner_dict
        }), 200

    @app.route('/api/matching/manual-by-code', methods=['POST'])
    @jwt_required()
    def manual_match_by_code():
        user_id = _get_jwt_user_id()
        if not user_id:
            return jsonify({'error': '缺少认证信息'}), 401
        data = request.get_json() or {}
        raw_code = data.get('match_code') or data.get('code') or ''
        code = str(raw_code).strip().upper()
        if not code:
            return jsonify({'error': '缺少匹配码'}), 400
        if not code.startswith('#'):
            code = f'#{code}'
        if not re.fullmatch(r'#[0-9A-F]{6}', code):
            return jsonify({'error': '匹配码格式不正确'}), 400
        match_code = MatchCode.query.filter_by(code=code).first()
        if not match_code:
            return jsonify({'error': '未找到该匹配码'}), 404
        partner_id = match_code.user_id
        if int(partner_id) == int(user_id):
            return jsonify({'error': '不能添加自己'}), 400
        user = User.query.get_or_404(user_id)
        partner = User.query.get_or_404(partner_id)
        match = _simulate_match_record(user, partner, 'chatting', 0, False, False, 0.88)
        return jsonify({'message': '匹配成功', 'data': match.to_dict(current_user_id=user.id)}), 200

    # ==================== 用户相关 API ====================

    @app.route('/api/users/profile', methods=['GET'])
    @jwt_required()
    def get_profile():
        """获取自己的资料"""
        user_id = _get_jwt_user_id()
        if not user_id:
            return jsonify({'error': '缺少认证信息'}), 401
        user = User.query.get_or_404(user_id)

        return jsonify({'user': user.to_dict(include_sensitive=True)}), 200

    @app.route('/api/users/profile', methods=['PUT'])
    @jwt_required()
    def update_profile():
        user_id = _get_jwt_user_id()
        if not user_id:
            return jsonify({'error': '缺少认证信息'}), 401
        user = User.query.get_or_404(user_id)
        data = request.get_json() or {}

        # Only nickname, age, gender are required; city & contact are optional
        required_fields = ['nickname', 'age', 'gender']
        for field in required_fields:
            if field not in data or data[field] in (None, ''):
                return jsonify({'error': f'缺少字段: {field}'}), 400

        try:
            age_value = int(data.get('age'))
        except (TypeError, ValueError):
            return jsonify({'error': '年龄格式不正确'}), 400
        if age_value < 18:
            return jsonify({'error': '年龄必须满18岁'}), 400

        gender_value = data.get('gender')
        if gender_value not in ('male', 'female', 'other'):
            return jsonify({'error': '性别选项不正确'}), 400

        nickname = str(data.get('nickname') or '').strip()

        # contact: optional; if provided, check uniqueness
        raw_contact = str(data.get('contact') or '').strip()
        if raw_contact:
            existing_user = User.query.filter(
                (User.contact == raw_contact) & (User.id != user_id)
            ).first()
            if existing_user:
                return jsonify({'error': '联系方式已被使用'}), 409
            user.contact = raw_contact

        user.nickname = nickname
        user.age = age_value
        user.gender = gender_value
        user.city = str(data.get('city') or '').strip() or None
        user.school_career = data.get('school_career')
        db.session.commit()

        return jsonify({'user': user.to_dict(include_sensitive=True)}), 200

    @app.route('/api/users/delete', methods=['DELETE'])
    @jwt_required()
    def delete_account():
        user_id = _get_jwt_user_id()
        if not user_id:
            return jsonify({'error': '缺少认证信息'}), 401
        user = User.query.get_or_404(user_id)

        matches = Match.query.filter(
            (Match.user_id == user_id) | (Match.matched_user_id == user_id)
        ).all()
        for match in matches:
            db.session.delete(match)

        Rating.query.filter(
            (Rating.rater_id == user_id) | (Rating.rated_user_id == user_id)
        ).delete(synchronize_session=False)

        ChatMessage.query.filter(ChatMessage.sender_id == user_id).delete(synchronize_session=False)
        QuestionAnswer.query.filter(QuestionAnswer.user_id == user_id).delete(synchronize_session=False)
        Purchase.query.filter(Purchase.user_id == user_id).delete(synchronize_session=False)
        MatchCode.query.filter(MatchCode.user_id == user_id).delete(synchronize_session=False)

        db.session.delete(user)
        db.session.commit()

        return jsonify({'message': '账号已注销', 'data': 'deleted'}), 200

    @app.route('/api/users/<int:user_id>/profile', methods=['GET'])
    @jwt_required()
    def get_user_profile(user_id):
        """获取用户资料 (需解锁)"""
        current_user_id = _get_jwt_user_id()
        if not current_user_id:
            return jsonify({'error': '缺少认证信息'}), 401

        # 检查是否有匹配记录且已解锁
        match = Match.query.filter(
            ((Match.user_id == current_user_id) & (Match.matched_user_id == user_id)) |
            ((Match.user_id == user_id) & (Match.matched_user_id == current_user_id))
        ).first()

        if not match or not match.is_unlocked:
            return jsonify({'error': '无权访问此用户资料'}), 403

        user = User.query.get_or_404(user_id)

        return jsonify({'user': user.to_dict(include_sensitive=True)}), 200

    @app.route('/api/users/matches-count', methods=['GET'])
    @jwt_required()
    def get_matches_count():
        """获取剩余匹配次数"""
        user_id = _get_jwt_user_id()
        if not user_id:
            return jsonify({'error': '缺少认证信息'}), 401
        user = User.query.get_or_404(user_id)

        return jsonify({'matches_left': user.remaining_matches}), 200

    @app.route('/api/users/purchase-matches', methods=['POST'])
    @jwt_required()
    def purchase_matches():
        """购买匹配次数 (模拟接口)"""
        user_id = _get_jwt_user_id()
        if not user_id:
            return jsonify({'error': '缺少认证信息'}), 401
        data = request.get_json()

        if 'matches_added' not in data or 'amount' not in data:
            return jsonify({'error': '缺少必要字段'}), 400

        user = User.query.get_or_404(user_id)

        # 创建购买记录
        purchase = Purchase(
            user_id=user_id,
            matches_added=data['matches_added'],
            amount=data['amount'],
            payment_method=data.get('payment_method', 'iap_apple'),
            transaction_id=data.get('transaction_id'),
            status='completed'
        )

        # 增加匹配次数
        user.remaining_matches += data['matches_added']

        db.session.add(purchase)
        db.session.commit()

        return jsonify({
            'message': '购买成功',
            'matches_added': data['matches_added'],
            'matches_left': user.remaining_matches
        }), 200

    @app.route('/api/users/match-code', methods=['GET'])
    @jwt_required()
    def get_match_code():
        """获取自己的匹配代码"""
        user_id = _get_jwt_user_id()
        if not user_id:
            return jsonify({'error': '缺少认证信息'}), 401
        match_code = MatchCode.query.filter_by(user_id=user_id).first()

        if not match_code:
            # 生成新代码
            match_code = MatchCode(
                user_id=user_id,
                code=generate_match_code()
            )
            db.session.add(match_code)
            db.session.commit()

        return jsonify({'code': match_code.code}), 200

    # ==================== 内容安全 API (Apple Guideline 1.2) ====================

    OFFENSIVE_KEYWORDS = [
        # Add domain-appropriate terms; this list is intentionally minimal for demo
        'spam', 'scam', 'nude', 'porn',
    ]

    def _contains_offensive_content(text):
        """Basic content filter — flag if text contains known offensive keywords."""
        lower = (text or '').lower()
        return any(kw in lower for kw in OFFENSIVE_KEYWORDS)

    @app.route('/api/users/report', methods=['POST'])
    @jwt_required()
    def report_user():
        """举报不当内容或滥用用户 — Apple Guideline 1.2"""
        reporter_id = _get_jwt_user_id()
        if not reporter_id:
            return jsonify({'error': '缺少认证信息'}), 401
        data = request.get_json() or {}
        reported_user_id = data.get('reported_user_id')
        if not reported_user_id:
            return jsonify({'error': '缺少 reported_user_id'}), 400
        if int(reported_user_id) == int(reporter_id):
            return jsonify({'error': '不能举报自己'}), 400
        User.query.get_or_404(reported_user_id)
        reason = str(data.get('reason') or '').strip()[:255]
        match_id = data.get('match_id')
        report = UserReport(
            reporter_id=reporter_id,
            reported_user_id=reported_user_id,
            match_id=match_id,
            reason=reason or None,
            status='pending'
        )
        db.session.add(report)
        db.session.commit()
        return jsonify({'message': '举报已提交，我们将在24小时内处理', 'report_id': report.id}), 201

    @app.route('/api/users/block', methods=['POST'])
    @jwt_required()
    def block_user():
        """屏蔽用户 — Apple Guideline 1.2"""
        blocker_id = _get_jwt_user_id()
        if not blocker_id:
            return jsonify({'error': '缺少认证信息'}), 401
        data = request.get_json() or {}
        blocked_id = data.get('blocked_user_id')
        if not blocked_id:
            return jsonify({'error': '缺少 blocked_user_id'}), 400
        if int(blocked_id) == int(blocker_id):
            return jsonify({'error': '不能屏蔽自己'}), 400
        User.query.get_or_404(blocked_id)
        existing = BlockedUser.query.filter_by(blocker_id=blocker_id, blocked_id=blocked_id).first()
        if existing:
            return jsonify({'message': '已经屏蔽该用户'}), 200
        block = BlockedUser(blocker_id=blocker_id, blocked_id=blocked_id)
        db.session.add(block)
        db.session.commit()
        return jsonify({'message': '已屏蔽该用户'}), 201

    @app.route('/api/users/block-list', methods=['GET'])
    @jwt_required()
    def get_block_list():
        """获取已屏蔽用户列表"""
        user_id = _get_jwt_user_id()
        if not user_id:
            return jsonify({'error': '缺少认证信息'}), 401
        blocks = BlockedUser.query.filter_by(blocker_id=user_id).all()
        return jsonify({'blocked_users': [b.blocked_id for b in blocks]}), 200

    @app.route('/api/chat/messages/<int:message_id>', methods=['DELETE'])
    @jwt_required()
    def delete_message(message_id):
        """删除自己的消息 — Apple Guideline 1.2: users can remove own posts"""
        user_id = _get_jwt_user_id()
        if not user_id:
            return jsonify({'error': '缺少认证信息'}), 401
        msg = ChatMessage.query.get_or_404(message_id)
        if msg.sender_id != user_id:
            return jsonify({'error': '只能删除自己发送的消息'}), 403
        db.session.delete(msg)
        db.session.commit()
        socketio.emit('message_deleted', {'message_id': message_id, 'match_id': msg.match_id},
                      room=f'match_{msg.match_id}')
        return jsonify({'message': '消息已删除', 'message_id': message_id}), 200

    # ==================== SocketIO 事件处理 ====================

    _sid_user_map = {}

    @socketio.on('connect')
    def handle_connect():
        """客户端连接 - 验证JWT"""
        token = request.args.get('token')
        if not token:
            auth_header = request.headers.get('Authorization', '')
            if auth_header.startswith('Bearer '):
                token = auth_header[7:]
        if not token:
            logger.warning(f'SocketIO connect rejected (no token): {request.sid}')
            return False
        try:
            from flask_jwt_extended import decode_token
            decoded = decode_token(token)
            user_id = int(decoded['sub'])
            _sid_user_map[request.sid] = user_id
            logger.info(f'Client connected: {request.sid} (user_id={user_id})')
        except Exception as e:
            logger.warning(f'SocketIO connect rejected (invalid token): {request.sid} - {e}')
            return False

    @socketio.on('disconnect')
    def handle_disconnect():
        """客户端断开"""
        _sid_user_map.pop(request.sid, None)
        logger.info(f'Client disconnected: {request.sid}')

    @socketio.on('join_match')
    def handle_join_match(data):
        """加入匹配聊天室"""
        match_id = data.get('match_id')
        if match_id:
            room = f'match_{match_id}'
            join_room(room)
            emit('joined_room', {'room': room})
            logger.info(f'Client {request.sid} joined room: {room}')

    @socketio.on('leave_match')
    def handle_leave_match(data):
        """离开匹配聊天室"""
        match_id = data.get('match_id')
        if match_id:
            room = f'match_{match_id}'
            leave_room(room)
            emit('left_room', {'room': room})
            logger.info(f'Client {request.sid} left room: {room}')

    @socketio.on('send_message')
    def handle_send_message(data):
        """处理WebSocket消息"""
        authenticated_user_id = _sid_user_map.get(request.sid)
        match_id = data.get('match_id')
        message = data.get('message')
        user_id = authenticated_user_id or data.get('user_id')

        if not match_id or not message or not user_id:
            return

        # 验证权限
        match = Match.query.get(match_id)
        if not match:
            return

        if match.user_id != user_id and match.matched_user_id != user_id:
            return

        # 创建消息
        msg = ChatMessage(
            match_id=match_id,
            sender_id=user_id,
            message=message,
            message_type=data.get('message_type', 'text')
        )

        db.session.add(msg)

        # 更新匹配消息计数
        match.chat_message_count += 1

        db.session.commit()

        # 广播消息到房间
        room = f'match_{match_id}'
        emit('new_message', msg.to_dict(), room=room, include_self=False)

        _handle_ai_reply_request(match, user_id, message)

    # ==================== 价值观探索 API ====================

    @app.route('/api/values/profile', methods=['GET'])
    @jwt_required()
    def get_values_profile():
        """获取当前用户的价值观雷达图数据（按section聚合）"""
        user_id = get_jwt_identity()
        answers = QuestionAnswer.query.filter_by(user_id=user_id).all()

        if not answers:
            return jsonify({'data': {'sections': {}, 'total_questions': 0, 'completed_at': None}}), 200

        # 批量预加载所有相关Question（消除N+1）
        question_ids = [a.question_id for a in answers]
        questions = {q.id: q for q in Question.query.filter(Question.id.in_(question_ids)).all()}

        # 按section聚合平均分
        section_scores = {}
        section_counts = {}
        for ans in answers:
            q = questions.get(ans.question_id)
            if q:
                sec = q.section
                section_scores[sec] = section_scores.get(sec, 0.0) + ans.answer
                section_counts[sec] = section_counts.get(sec, 0) + 1

        sections_avg = {}
        for sec in section_scores:
            cnt = section_counts[sec]
            if cnt > 0:
                sections_avg[sec] = round(section_scores[sec] / cnt, 2)

        latest = max((a.updated_at for a in answers), default=None)

        return jsonify({
            'data': {
                'sections': sections_avg,
                'total_questions': len(answers),
                'completed_at': latest.isoformat() if latest else None
            }
        }), 200

    @app.route('/api/values/insights', methods=['GET'])
    @jwt_required()
    def get_values_insights():
        """获取当前用户在各维度的百分位排名（与全体用户对比）"""
        user_id = get_jwt_identity()

        # 获取所有完成问卷的用户数
        user_answer_counts = db.session.query(
            QuestionAnswer.user_id, db.func.count(QuestionAnswer.id)
        ).group_by(QuestionAnswer.user_id).having(db.func.count(QuestionAnswer.id) >= 66).all()

        total_users = len(user_answer_counts)
        if total_users == 0:
            return jsonify({'data': {'percentiles': {}, 'total_users': 0}}), 200

        completed_user_ids = [uid for uid, cnt in user_answer_counts]

        # 批量预加载所有相关Question（消除N+1）
        all_answers = QuestionAnswer.query.filter(
            QuestionAnswer.user_id.in_(completed_user_ids)
        ).all()
        question_ids = list(set(a.question_id for a in all_answers))
        questions_map = {q.id: q for q in Question.query.filter(Question.id.in_(question_ids)).all()}

        # 当前用户按section平均
        my_answers = [a for a in all_answers if a.user_id == user_id]
        my_section_avg = {}
        my_section_counts = {}
        for ans in my_answers:
            q = questions_map.get(ans.question_id)
            if q:
                my_section_avg[q.section] = my_section_avg.get(q.section, 0.0) + ans.answer
                my_section_counts[q.section] = my_section_counts.get(q.section, 0) + 1
        for sec in my_section_avg:
            cnt = my_section_counts.get(sec, 0)
            if cnt > 0:
                my_section_avg[sec] = round(my_section_avg[sec] / cnt, 2)

        # 全体用户按section平均（使用预加载数据，零额外查询）
        all_section_avgs = {}
        for uid in completed_user_ids:
            their_answers = [a for a in all_answers if a.user_id == uid]
            sec_sums = {}
            sec_cnts = {}
            for ans in their_answers:
                q = questions_map.get(ans.question_id)
                if q:
                    sec_sums[q.section] = sec_sums.get(q.section, 0.0) + ans.answer
                    sec_cnts[q.section] = sec_cnts.get(q.section, 0) + 1
            for sec in sec_sums:
                avg = sec_sums[sec] / sec_cnts[sec] if sec_cnts[sec] > 0 else 0
                all_section_avgs.setdefault(sec, []).append(avg)

        # 计算百分位
        section_labels_en = {
            'core_values': 'Core Values', 'lifestyle': 'Lifestyle',
            'political': 'Social Views', 'relationship': 'Relationships',
            'personality': 'Personality', 'communication': 'Communication'
        }
        section_labels_zh = {
            'core_values': '核心价值观', 'lifestyle': '生活方式',
            'political': '社会观点', 'relationship': '人际关系',
            'personality': '性格特质', 'communication': '沟通风格'
        }
        percentiles = {}
        for sec in my_section_avg:
            my_score = my_section_avg[sec]
            all_scores = all_section_avgs.get(sec, [])
            if all_scores:
                below = sum(1 for s in all_scores if s < my_score)
                pct = round(below / len(all_scores) * 100)
                percentiles[sec] = {
                    'score': my_score,
                    'percentile': pct,
                    'label_en': section_labels_en.get(sec, sec),
                    'label_zh': section_labels_zh.get(sec, sec),
                    'label': section_labels_en.get(sec, sec),
                    'total_users': len(all_scores)
                }

        return jsonify({
            'data': {
                'percentiles': percentiles,
                'total_users': total_users,
                'my_scores': my_section_avg
            }
        }), 200

    @app.route('/api/values/daily-card', methods=['GET'])
    @jwt_required()
    def get_daily_values_card():
        """每日价值观思考卡片 — 基于用户弱维度个性化推荐"""
        import hashlib
        from datetime import date

        user_id = get_jwt_identity()
        lang = request.args.get('lang', 'en')  # zh or en

        # 用当天日期 + user_id 生成确定性卡片索引（每个用户看到的卡片不同）
        today_str = date.today().isoformat()
        hash_val = int(hashlib.md5(f'{today_str}:{user_id}'.encode()).hexdigest(), 16)

        # 尝试基于用户弱维度推荐卡片（提升个性化体验）
        preferred_dimension = None
        my_answers = QuestionAnswer.query.filter_by(user_id=user_id).all()
        if my_answers:
            q_ids = [a.question_id for a in my_answers]
            q_map = {q.id: q for q in Question.query.filter(Question.id.in_(q_ids)).all()}
            sec_sums = {}
            sec_cnts = {}
            for ans in my_answers:
                q = q_map.get(ans.question_id)
                if q:
                    sec_sums[q.section] = sec_sums.get(q.section, 0.0) + ans.answer
                    sec_cnts[q.section] = sec_cnts.get(q.section, 0) + 1
            if sec_sums:
                weakest = min(sec_sums, key=lambda s: sec_sums.get(s, 0) / max(sec_cnts.get(s, 1), 1))
                preferred_dimension = weakest

        cards_zh = [
            {'title': '诚实与善意', 'question': '如果诚实会伤害一个朋友的感情，你会选择说实话还是善意的谎言？', 'dimension': 'core_values'},
            {'title': '独处与社交', 'question': '一个完美的周末，你更愿意独自充电，还是和朋友们热闹一场？', 'dimension': 'lifestyle'},
            {'title': '传统与创新', 'question': '面对一个重要的生活决定，你会更倾向于遵循传统方式，还是尝试全新的路径？', 'dimension': 'core_values'},
            {'title': '竞争与合作', 'question': '在工作中，你认为竞争能激发潜力，还是合作能创造更大价值？', 'dimension': 'personality'},
            {'title': '理想与现实', 'question': '你是那个坚持理想不妥协的人，还是愿意为了结果做出务实调整的人？', 'dimension': 'relationship'},
            {'title': '表达与倾听', 'question': '在一场讨论中，你更享受表达自己的观点，还是倾听他人的想法？', 'dimension': 'communication'},
            {'title': '稳定与冒险', 'question': '如果有一份稳定的工作和一个充满未知的机会，你会怎么选？', 'dimension': 'lifestyle'},
            {'title': '个人与集体', 'question': '当个人利益和团队利益冲突时，你更看重哪一边？', 'dimension': 'political'},
            {'title': '直觉与分析', 'question': '面对重大选择时，你更信任自己的直觉，还是数据和逻辑？', 'dimension': 'personality'},
            {'title': '给予与接受', 'question': '在一段关系中，你更习惯主动关心对方，还是等待对方先表达？', 'dimension': 'communication'},
            {'title': '自由与责任', 'question': '你认为自由更重要，还是承担责任更能体现一个人的价值？', 'dimension': 'core_values'},
            {'title': '过程与结果', 'question': '做一件事，你更在意过程中的体验，还是最终的结果？', 'dimension': 'lifestyle'},
            {'title': '独立与依赖', 'question': '遇到困难时，你的第一反应是靠自己解决，还是寻求帮助？', 'dimension': 'relationship'},
            {'title': '计划与随性', 'question': '旅行时，你更愿意提前规划好每个细节，还是走到哪算哪？', 'dimension': 'personality'},
        ]

        cards_en = [
            {'title': 'Honesty vs Kindness', 'question': 'If being honest would hurt a friend\'s feelings, would you tell the truth or choose a white lie?', 'dimension': 'core_values'},
            {'title': 'Solitude vs Socializing', 'question': 'For a perfect weekend, would you rather recharge alone or party with friends?', 'dimension': 'lifestyle'},
            {'title': 'Tradition vs Innovation', 'question': 'Facing a big life decision, would you follow tradition or try a completely new path?', 'dimension': 'core_values'},
            {'title': 'Competition vs Cooperation', 'question': 'Do you believe competition drives potential, or collaboration creates more value?', 'dimension': 'personality'},
            {'title': 'Idealism vs Pragmatism', 'question': 'Are you the one who sticks to ideals, or the one who makes pragmatic adjustments?', 'dimension': 'relationship'},
            {'title': 'Speaking vs Listening', 'question': 'In a discussion, do you enjoy expressing your views or listening to others?', 'dimension': 'communication'},
            {'title': 'Stability vs Adventure', 'question': 'Given a stable job and an unknown opportunity, which would you choose?', 'dimension': 'lifestyle'},
            {'title': 'Individual vs Collective', 'question': 'When personal and team interests conflict, which do you prioritize?', 'dimension': 'political'},
            {'title': 'Intuition vs Analysis', 'question': 'For major decisions, do you trust your gut or rely on data and logic?', 'dimension': 'personality'},
            {'title': 'Giving vs Receiving', 'question': 'In relationships, do you naturally give care or wait for the other person to express first?', 'dimension': 'communication'},
            {'title': 'Freedom vs Responsibility', 'question': 'Which matters more — personal freedom, or the responsibility that defines your worth?', 'dimension': 'core_values'},
            {'title': 'Process vs Outcome', 'question': 'When doing something, do you care more about the experience or the result?', 'dimension': 'lifestyle'},
            {'title': 'Independence vs Support', 'question': 'When facing difficulties, is your first instinct to solve it alone or ask for help?', 'dimension': 'relationship'},
            {'title': 'Planning vs Spontaneity', 'question': 'When traveling, do you plan every detail or go with the flow?', 'dimension': 'personality'},
        ]

        # 优先选择用户弱维度的卡片，否则用hash选
        if preferred_dimension:
            dim_cards = [i for i, c in enumerate(cards_zh) if c['dimension'] == preferred_dimension]
            if dim_cards:
                idx = dim_cards[hash_val % len(dim_cards)]
            else:
                idx = hash_val % len(cards_zh)
        else:
            idx = hash_val % len(cards_zh)

        # 查询互动记录
        interaction = DailyCardInteraction.query.filter_by(
            user_id=user_id, card_date=today_str
        ).first()

        result = {
            'title_zh': cards_zh[idx]['title'],
            'question_zh': cards_zh[idx]['question'],
            'title_en': cards_en[idx]['title'],
            'question_en': cards_en[idx]['question'],
            'dimension': cards_zh[idx]['dimension'],
            'date': today_str,
            'has_read': interaction.has_read if interaction else False,
            'has_answered': interaction.has_answered if interaction else False,
            'answer_text': interaction.answer_text if interaction else None
        }

        # 自动标记为已读
        if not interaction:
            interaction = DailyCardInteraction(
                user_id=user_id, card_date=today_str, has_read=True
            )
            db.session.add(interaction)
            db.session.commit()
        elif not interaction.has_read:
            interaction.has_read = True
            db.session.commit()

        return jsonify({'data': result}), 200

    @app.route('/api/values/daily-card/respond', methods=['POST'])
    @jwt_required()
    def respond_daily_card():
        """用户回答每日卡片"""
        from datetime import date
        user_id = get_jwt_identity()
        data = request.get_json() or {}
        answer_text = (data.get('answer_text') or '').strip()
        if not answer_text:
            return jsonify({'error': '请输入回答内容'}), 400

        today_str = date.today().isoformat()
        interaction = DailyCardInteraction.query.filter_by(
            user_id=user_id, card_date=today_str
        ).first()

        if not interaction:
            interaction = DailyCardInteraction(
                user_id=user_id, card_date=today_str,
                has_read=True, has_answered=True, answer_text=answer_text
            )
            db.session.add(interaction)
        else:
            interaction.has_answered = True
            interaction.answer_text = answer_text

        db.session.commit()
        return jsonify({'message': '回答已保存', 'data': interaction.to_dict()}), 200

    # ==================== 错误处理 ====================

    @app.errorhandler(404)
    def not_found(error):
        return jsonify({'error': '资源不存在'}), 404

    @app.errorhandler(500)
    def internal_error(error):
        db.session.rollback()
        return jsonify({'error': '服务器内部错误'}), 500

    # ========== 官网路由 ==========
    from flask import render_template, send_from_directory

    @app.route('/')
    def index():
        """官网首页"""
        return render_template('index.html')

    @app.route('/privacy')
    def privacy():
        """隐私政策页面"""
        return render_template('privacy.html')

    @app.route('/favicon.ico')
    def favicon():
        """Favicon"""
        return send_from_directory(os.path.join(app.root_path, '..'), 'tubiao.jpg', mimetype='image/jpeg')

    # ========== 官网路由结束 ==========

    return app, socketio


# 创建应用实例
app, socketio = create_app(os.getenv('FLASK_ENV', 'default'))


if __name__ == '__main__':
    # 运行服务器
    port = int(os.getenv('PORT', 9021))
    logger.info(f"🚀 VitaDuo Backend Server 启动在端口 {port}")
    debug_mode = os.getenv('FLASK_DEBUG', 'false').lower() == 'true'
    socketio.run(app, host='0.0.0.0', port=port, debug=debug_mode)
