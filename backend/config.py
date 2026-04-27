"""
VitaDuo Backend Configuration
"""
import os
from datetime import timedelta


class Config:
    """基础配置"""
    SECRET_KEY = os.getenv('SECRET_KEY')
    if not SECRET_KEY:
        raise RuntimeError("SECRET_KEY must be set in environment variables")

    DEBUG = os.getenv('DEBUG', 'False') == 'True'

    # 数据库配置 - 支持 PostgreSQL 和 MySQL
    db_url = os.getenv('DATABASE_URL', '')
    if db_url.startswith('postgres://'):
        db_url = db_url.replace('postgres://', 'postgresql://', 1)
    SQLALCHEMY_DATABASE_URI = db_url or 'sqlite:///date_drop.db'
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {
        'pool_size': 10,
        'pool_recycle': 3600,
        'max_overflow': 20,
        'pool_pre_ping': True
    }

    # JWT配置
    JWT_SECRET_KEY = os.getenv('JWT_SECRET_KEY')
    if not JWT_SECRET_KEY:
        raise RuntimeError("JWT_SECRET_KEY must be set in environment variables")
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(days=30)
    JWT_TOKEN_LOCATION = ['headers']

    # CORS配置
    _cors_origins = os.getenv(
        'CORS_ORIGINS',
        'https://dd3.tpr.wales,https://vitaduo.tpr.wales,http://localhost:3000'
    )
    CORS_ORIGINS = [o.strip() for o in _cors_origins.split(',') if o.strip()]

    # SocketIO配置
    SOCKETIO_ASYNC_MODE = 'eventlet'
    SOCKETIO_CORS_ALLOWED_ORIGINS = CORS_ORIGINS

    # 匹配配置
    MATCHES_PER_WEEK = 3
    MATCH_UNLOCK_THRESHOLD = 4
    NEW_USER_MATCHES = 3

    # 聊天配置
    MIN_MESSAGES_TO_COMPLETE = 20


class DevelopmentConfig(Config):
    """开发环境配置 - 允许使用默认密钥"""
    SECRET_KEY = os.getenv('SECRET_KEY', 'dev-secret-key-change-in-production')
    JWT_SECRET_KEY = os.getenv('JWT_SECRET_KEY', 'jwt-secret-key-change-in-production')
    DEBUG = True


class ProductionConfig(Config):
    """生产环境配置"""
    DEBUG = False


config = {
    'development': DevelopmentConfig,
    'production': ProductionConfig,
    'default': DevelopmentConfig
}
