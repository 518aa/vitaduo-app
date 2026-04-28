"""
VitaDuo 匹配算法模块
基于余弦相似度计算用户价值观匹配度
"""
import numpy as np
from sklearn.metrics.pairwise import cosine_similarity
from models import User, QuestionAnswer, Question, Match, Rating, db
from datetime import datetime, timedelta
import random
import string


class MatchingAlgorithm:
    """匹配算法类"""

    def __init__(self, weight_sensitive=True):
        """
        初始化匹配算法

        Args:
            weight_sensitive: 是否使用加权相似度 (敏感问题和核心问题权重更高)
        """
        self.weight_sensitive = weight_sensitive
        self.question_weights = self._load_question_weights()

    def _load_question_weights(self):
        """加载题目权重"""
        weights = {}
        questions = Question.query.all()
        for q in questions:
            weights[q.id] = q.weight if self.weight_sensitive else 1.0
        return weights

    def get_user_answer_vector(self, user_id):
        """
        获取用户的答案向量 (66维)

        Args:
            user_id: 用户ID

        Returns:
            numpy array: 66维答案向量
        """
        answers = QuestionAnswer.query.filter_by(user_id=user_id).all()

        if len(answers) != 66:
            raise ValueError(f"用户 {user_id} 的答案不完整: {len(answers)}/66")

        # 构建66维向量
        vector = np.zeros(66)
        for answer in answers:
            question_id = answer.question_id
            if 1 <= question_id <= 66:
                vector[question_id - 1] = answer.answer

        return vector

    def calculate_weighted_cosine_similarity(self, vector_a, vector_b):
        """
        计算加权余弦相似度

        Args:
            vector_a: 用户A的答案向量 (66维)
            vector_b: 用户B的答案向量 (66维)

        Returns:
            float: 相似度分数 (0-1之间)
        """
        # 应用权重
        weighted_a = vector_a.copy()
        weighted_b = vector_b.copy()

        for i in range(66):
            question_id = i + 1
            weight = self.question_weights.get(question_id, 1.0)
            weighted_a[i] *= weight
            weighted_b[i] *= weight

        # 计算余弦相似度
        weighted_a = weighted_a.reshape(1, -1)
        weighted_b = weighted_b.reshape(1, -1)

        similarity = cosine_similarity(weighted_a, weighted_b)[0][0]

        return float(similarity)

    def calculate_simple_cosine_similarity(self, vector_a, vector_b):
        """
        计算简单余弦相似度 (无权重)

        Args:
            vector_a: 用户A的答案向量
            vector_b: 用户B的答案向量

        Returns:
            float: 相似度分数 (0-1之间)
        """
        vector_a = vector_a.reshape(1, -1)
        vector_b = vector_b.reshape(1, -1)

        similarity = cosine_similarity(vector_a, vector_b)[0][0]

        return float(similarity)

    def calculate_similarity(self, user_id_a, user_id_b):
        """
        计算两个用户之间的相似度

        Args:
            user_id_a: 用户A的ID
            user_id_b: 用户B的ID

        Returns:
            float: 相似度分数 (0-1之间)
        """
        vector_a = self.get_user_answer_vector(user_id_a)
        vector_b = self.get_user_answer_vector(user_id_b)

        if self.weight_sensitive:
            return self.calculate_weighted_cosine_similarity(vector_a, vector_b)
        else:
            return self.calculate_simple_cosine_similarity(vector_a, vector_b)

    def find_top_matches(self, user_id, limit=1, exclude_user_ids=None):
        """
        为用户找到最匹配的Top N用户

        Args:
            user_id: 当前用户ID
            limit: 返回匹配数量 (默认3)
            exclude_user_ids: 排除的用户ID列表

        Returns:
            list: [(matched_user_id, similarity_score), ...]
        """
        if exclude_user_ids is None:
            exclude_user_ids = []

        # 排除自己和已匹配的用户
        exclude_user_ids.append(user_id)

        current_user = User.query.get(user_id)
        if not current_user:
            raise ValueError(f"用户 {user_id} 不存在")

        # 获取当前用户的答案向量
        try:
            user_vector = self.get_user_answer_vector(user_id)
        except ValueError as e:
            raise ValueError(f"用户 {user_id} 无法进行匹配: {str(e)}")

        # 获取所有已完成问卷的用户
        all_users = User.query.filter(
            User.id.notin_(exclude_user_ids),
            User.gender != current_user.gender
        ).all()

        # 检查每个用户的答案完整性
        valid_matches = []
        for other_user in all_users:
            try:
                other_vector = self.get_user_answer_vector(other_user.id)
                similarity = self.calculate_weighted_cosine_similarity(user_vector, other_vector)
                valid_matches.append((other_user.id, similarity))
            except ValueError:
                # 跳过答案不完整的用户
                continue

        # 按相似度降序排序
        valid_matches.sort(key=lambda x: x[1], reverse=True)

        # 返回Top N
        return valid_matches[:limit]

    def create_matches(self, user_id, limit=1):
        """
        为用户创建匹配记录

        Args:
            user_id: 用户ID
            limit: 匹配数量 (默认3)

        Returns:
            list: 创建的Match对象列表
        """
        # 获取本周已匹配的用户
        one_week_ago = datetime.utcnow() - timedelta(days=7)
        recent_matches = Match.query.filter(
            Match.user_id == user_id,
            Match.created_at >= one_week_ago
        ).all()

        exclude_user_ids = [m.matched_user_id for m in recent_matches]

        # 查找Top匹配
        top_matches = self.find_top_matches(user_id, limit=limit, exclude_user_ids=exclude_user_ids)

        if not top_matches:
            return []

        # 创建匹配记录
        created_matches = []
        for matched_user_id, similarity_score in top_matches:
            # 检查是否已存在匹配记录
            existing = Match.query.filter_by(
                user_id=user_id,
                matched_user_id=matched_user_id
            ).first()

            if existing:
                created_matches.append(existing)
                continue

            # 创建新匹配
            new_match = Match(
                user_id=user_id,
                matched_user_id=matched_user_id,
                similarity_score=similarity_score,
                status='pending'
            )

            db.session.add(new_match)
            created_matches.append(new_match)

        db.session.commit()

        return created_matches


def generate_match_code():
    """
    生成6位随机匹配代码 (如 #A7F3C2)

    Returns:
        str: 匹配代码 (如 #A7F3C2)
    """
    # 生成6位随机十六进制字符
    code = '#' + ''.join(random.choices('0123456789ABCDEF', k=6))
    return code


def check_unlock_status(match_id):
    """
    检查匹配是否可以解锁详细资料

    Args:
        match_id: 匹配ID

    Returns:
        tuple: (can_unlock: bool, reason: str)
    """
    match = Match.query.get_or_404(match_id)

    # 检查双方是否都已评分
    ratings = Rating.query.filter_by(match_id=match_id).all()

    if len(ratings) < 2:
        return False, "双方尚未完成评分"

    # 获取双方评分
    user1_score = None
    user2_score = None

    for rating in ratings:
        if rating.rater_id == match.user_id:
            user1_score = rating.score
        elif rating.rater_id == match.matched_user_id:
            user2_score = rating.score

    if user1_score is None or user2_score is None:
        return False, "双方评分未完成"

    # 检查是否双方都≥4分
    if user1_score >= 4 and user2_score >= 4:
        return True, "匹配成功"
    else:
        return False, f"评分不足 (用户1: {user1_score}分, 用户2: {user2_score}分)"


def unlock_match_profile(match_id):
    """
    解锁匹配对象的详细资料

    Args:
        match_id: 匹配ID

    Returns:
        bool: 是否成功解锁
    """
    can_unlock, reason = check_unlock_status(match_id)

    if can_unlock:
        match = Match.query.get(match_id)
        match.is_unlocked = True
        db.session.commit()
        return True

    return False


if __name__ == '__main__':
    # 测试匹配算法
    print("匹配算法模块加载成功")

    # 示例: 计算两个用户的相似度
    # algorithm = MatchingAlgorithm()
    # similarity = algorithm.calculate_similarity(user_id_a=1, user_id_b=2)
    # print(f"相似度: {similarity:.2f}")
