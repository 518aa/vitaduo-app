"""
VitaDuo 数据库模型
"""
from flask_sqlalchemy import SQLAlchemy
from datetime import datetime
import json

db = SQLAlchemy()


class User(db.Model):
    """用户模型"""
    __tablename__ = 'users'

    id = db.Column(db.Integer, primary_key=True)
    nickname = db.Column(db.String(50), nullable=False)
    age = db.Column(db.Integer, nullable=False)
    gender = db.Column(db.Enum('male', 'female', 'other', name='gender_enum'), nullable=False)
    school_career = db.Column(db.String(100), nullable=True)
    # city is now optional (Apple Guideline 5.1.1)
    city = db.Column(db.String(50), nullable=True)
    # contact is now optional — auto-generated if not supplied (Apple Guideline 5.1.1)
    contact = db.Column(db.String(100), unique=True, nullable=False)
    avatar_url = db.Column(db.String(255), nullable=True)
    remaining_matches = db.Column(db.Integer, default=3, nullable=False)
    is_verified = db.Column(db.Boolean, default=False, nullable=False)
    is_ai = db.Column(db.Boolean, default=False, nullable=False)
    ai_profile = db.Column(db.Text, nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # 关系
    answers = db.relationship('QuestionAnswer', backref='user', lazy='dynamic', cascade='all, delete-orphan')
    matches_as_user1 = db.relationship('Match', foreign_keys='Match.user_id', backref='user1', lazy='dynamic')
    matches_as_user2 = db.relationship('Match', foreign_keys='Match.matched_user_id', backref='user2', lazy='dynamic')
    sent_messages = db.relationship('ChatMessage', backref='sender', lazy='dynamic', foreign_keys='ChatMessage.sender_id')
    given_ratings = db.relationship('Rating', foreign_keys='Rating.rater_id', backref='rater', lazy='dynamic')
    received_ratings = db.relationship('Rating', foreign_keys='Rating.rated_user_id', backref='rated_user', lazy='dynamic')
    purchases = db.relationship('Purchase', backref='user', lazy='dynamic')
    match_code = db.relationship('MatchCode', backref='user', uselist=False, cascade='all, delete-orphan')

    def to_dict(self, include_sensitive=False):
        """转换为字典"""
        data = {
            'id': self.id,
            'nickname': self.nickname,
            'age': self.age,
            'gender': self.gender,
            'school_career': self.school_career,
            'city': self.city,
            'avatar_url': self.avatar_url,
            'matches_left': self.remaining_matches,
            'is_verified': self.is_verified,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }

        # 敏感信息仅在解锁后显示
        if include_sensitive:
            data['contact'] = self.contact

        return data

    def __repr__(self):
        return f'<User {self.id}: {self.nickname}>'


class Question(db.Model):
    """问卷题目模型"""
    __tablename__ = 'questions'

    id = db.Column(db.Integer, primary_key=True)
    text_cn = db.Column(db.Text, nullable=False)
    text_en = db.Column(db.Text, nullable=False)
    section = db.Column(
        db.Enum('core_values', 'lifestyle', 'political', 'relationship', 'personality', 'communication',
                name='section_enum'),
        nullable=False
    )
    question_type = db.Column(db.Enum('likert_7', 'choice_5', name='question_type_enum'), nullable=False)
    is_sensitive = db.Column(db.Boolean, default=False, nullable=False)
    weight = db.Column(db.Float, default=1.0, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    # 关系
    answers = db.relationship('QuestionAnswer', backref='question', lazy='dynamic')

    def to_dict(self, lang='zh'):
        """转换为字典"""
        return {
            'id': self.id,
            'text': self.text_cn if lang == 'zh' else self.text_en,
            'isLikert': self.question_type == 'likert_7',
            'isSensitive': self.is_sensitive,
            'section': self.section,
            'weight': self.weight
        }

    def __repr__(self):
        return f'<Question {self.id}: {self.text_cn[:20]}...>'


class QuestionAnswer(db.Model):
    """问卷答案模型"""
    __tablename__ = 'question_answers'

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    question_id = db.Column(db.Integer, db.ForeignKey('questions.id'), nullable=False)
    answer = db.Column(db.Integer, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # 唯一约束
    __table_args__ = (db.UniqueConstraint('user_id', 'question_id', name='unique_user_question'),)

    def to_dict(self):
        """转换为字典"""
        return {
            'id': self.id,
            'user_id': self.user_id,
            'question_id': self.question_id,
            'answer': self.answer,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }

    def __repr__(self):
        return f'<QuestionAnswer user={self.user_id} question={self.question_id} answer={self.answer}>'


class Match(db.Model):
    """匹配记录模型"""
    __tablename__ = 'matches'

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    matched_user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    similarity_score = db.Column(db.Float, nullable=False)
    status = db.Column(
        db.Enum('pending', 'chatting', 'completed', 'failed', name='match_status_enum'),
        default='pending',
        nullable=False
    )
    is_unlocked = db.Column(db.Boolean, default=False, nullable=False)
    chat_message_count = db.Column(db.Integer, default=0, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # 关系
    messages = db.relationship('ChatMessage', backref='match', lazy='dynamic', cascade='all, delete-orphan')
    ratings = db.relationship('Rating', backref='match', lazy='dynamic', cascade='all, delete-orphan')

    def to_dict(self, current_user_id=None):
        """转换为字典"""
        # 确定匹配对象的ID
        other_user_id = self.matched_user_id if self.user_id == current_user_id else self.user_id

        data = {
            'id': self.id,
            'user1_id': self.user_id,
            'user2_id': self.matched_user_id,
            'similarity_score': min(round(self.similarity_score * 100, 2), 99.9),
            'status': self.status,
            'is_unlocked': self.is_unlocked,
            'chat_message_count': self.chat_message_count,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }

        if current_user_id is not None:
            partner = User.query.get(other_user_id)
            data['partner_nickname'] = partner.nickname if partner else None

        return data

    def __repr__(self):
        return f'<Match {self.id}: {self.user_id} <-> {self.matched_user_id} ({self.status})>'


class ChatMessage(db.Model):
    """聊天消息模型"""
    __tablename__ = 'chat_messages'

    id = db.Column(db.Integer, primary_key=True)
    match_id = db.Column(db.Integer, db.ForeignKey('matches.id'), nullable=False)
    sender_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    message = db.Column(db.Text, nullable=False)
    message_type = db.Column(db.Enum('text', 'emoji', 'system', name='message_type_enum'), default='text')
    is_read = db.Column(db.Boolean, default=False, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def to_dict(self):
        """转换为字典"""
        return {
            'id': self.id,
            'match_id': self.match_id,
            'sender_id': self.sender_id,
            'content': self.message,
            'message_type': self.message_type,
            'is_read': self.is_read,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }

    def __repr__(self):
        return f'<ChatMessage {self.id}: match={self.match_id} sender={self.sender_id}>'


class Rating(db.Model):
    """评分记录模型"""
    __tablename__ = 'ratings'

    id = db.Column(db.Integer, primary_key=True)
    match_id = db.Column(db.Integer, db.ForeignKey('matches.id'), nullable=False)
    rater_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    rated_user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    score = db.Column(db.Integer, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    # 唯一约束: 每个匹配每人对每个人只能评一次
    __table_args__ = (db.UniqueConstraint('match_id', 'rater_id', name='unique_match_rater'),)

    def to_dict(self):
        """转换为字典"""
        return {
            'id': self.id,
            'match_id': self.match_id,
            'rater_id': self.rater_id,
            'rated_user_id': self.rated_user_id,
            'score': self.score,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }

    def __repr__(self):
        return f'<Rating {self.id}: rater={self.rater_id} rated={self.rated_user_id} score={self.score}>'


class Purchase(db.Model):
    """购买记录模型"""
    __tablename__ = 'purchases'

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    matches_added = db.Column(db.Integer, nullable=False)
    amount = db.Column(db.Numeric(10, 2), nullable=False)
    currency = db.Column(db.String(10), default='CNY')
    payment_method = db.Column(db.String(50), default='iap_apple')
    transaction_id = db.Column(db.String(100), nullable=True)
    status = db.Column(
        db.Enum('pending', 'completed', 'failed', 'refunded', name='purchase_status_enum'),
        default='pending',
        nullable=False
    )
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    completed_at = db.Column(db.DateTime, nullable=True)

    def to_dict(self):
        """转换为字典"""
        return {
            'id': self.id,
            'user_id': self.user_id,
            'matches_added': self.matches_added,
            'amount': float(self.amount),
            'currency': self.currency,
            'payment_method': self.payment_method,
            'transaction_id': self.transaction_id,
            'status': self.status,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'completed_at': self.completed_at.isoformat() if self.completed_at else None
        }

    def __repr__(self):
        return f'<Purchase {self.id}: user={self.user_id} +{self.matches_added} matches {self.status}>'


class MatchCode(db.Model):
    """匹配代码模型"""
    __tablename__ = 'match_codes'

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    code = db.Column(db.String(10), nullable=False, unique=True)
    is_active = db.Column(db.Boolean, default=True, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def to_dict(self):
        """转换为字典"""
        return {
            'id': self.id,
            'user_id': self.user_id,
            'code': self.code,
            'is_active': self.is_active,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }

    def __repr__(self):
        return f'<MatchCode {self.code} for user {self.user_id}>'


class UserReport(db.Model):
    """用户举报记录 — Apple Guideline 1.2: mechanism to flag objectionable content"""
    __tablename__ = 'user_reports'

    id = db.Column(db.Integer, primary_key=True)
    reporter_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    reported_user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    match_id = db.Column(db.Integer, db.ForeignKey('matches.id'), nullable=True)
    reason = db.Column(db.String(255), nullable=True)
    status = db.Column(
        db.Enum('pending', 'reviewed', 'actioned', 'dismissed', name='report_status_enum'),
        default='pending', nullable=False
    )
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    reviewed_at = db.Column(db.DateTime, nullable=True)

    def to_dict(self):
        return {
            'id': self.id,
            'reporter_id': self.reporter_id,
            'reported_user_id': self.reported_user_id,
            'match_id': self.match_id,
            'reason': self.reason,
            'status': self.status,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }

    def __repr__(self):
        return f'<UserReport {self.id}: reporter={self.reporter_id} reported={self.reported_user_id}>'


class BlockedUser(db.Model):
    """用户屏蔽记录 — Apple Guideline 1.2: mechanism to block abusive users"""
    __tablename__ = 'blocked_users'

    id = db.Column(db.Integer, primary_key=True)
    blocker_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    blocked_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    __table_args__ = (db.UniqueConstraint('blocker_id', 'blocked_id', name='unique_block_pair'),)

    def to_dict(self):
        return {
            'id': self.id,
            'blocker_id': self.blocker_id,
            'blocked_id': self.blocked_id,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }

    def __repr__(self):
        return f'<BlockedUser {self.blocker_id} -> {self.blocked_id}>'
