-- Date Drop 数据库建表脚本
-- MySQL数据库

-- 创建数据库
CREATE DATABASE IF NOT EXISTS date_drop CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE date_drop;

-- 用户表
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nickname VARCHAR(50) NOT NULL,
    age INT NOT NULL CHECK (age >= 18 AND age <= 100),
    gender ENUM('male', 'female', 'other') NOT NULL,
    school_career VARCHAR(100) DEFAULT NULL,
    city VARCHAR(50) NOT NULL,
    contact VARCHAR(100) NOT NULL,
    avatar_url VARCHAR(255) DEFAULT NULL,
    remaining_matches INT DEFAULT 3 CHECK (remaining_matches >= 0),
    is_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY unique_contact (contact),
    INDEX idx_remaining_matches (remaining_matches),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 问卷题目表
CREATE TABLE IF NOT EXISTS questions (
    id INT PRIMARY KEY,
    text_cn TEXT NOT NULL COMMENT '中文题干',
    text_en TEXT NOT NULL COMMENT '英文题干',
    section ENUM('core_values', 'lifestyle', 'political', 'relationship', 'personality', 'communication') NOT NULL,
    question_type ENUM('likert_7', 'choice_5') NOT NULL COMMENT 'likert_7: 7点量表, choice_5: 5点选择',
    is_sensitive BOOLEAN DEFAULT FALSE COMMENT '是否敏感问题',
    weight FLOAT DEFAULT 1.0 COMMENT '权重,核心问题可设为1.5',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 问卷答案表
CREATE TABLE IF NOT EXISTS question_answers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    question_id INT NOT NULL,
    answer INT NOT NULL COMMENT '根据题型: 1-7 或 1-5',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE,
    UNIQUE KEY unique_user_question (user_id, question_id),
    INDEX idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 匹配记录表
CREATE TABLE IF NOT EXISTS matches (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL COMMENT '发起匹配的用户',
    matched_user_id INT NOT NULL COMMENT '被匹配的用户',
    similarity_score FLOAT NOT NULL COMMENT '相似度分数 0-1',
    status ENUM('pending', 'chatting', 'completed', 'failed') DEFAULT 'pending',
    is_unlocked BOOLEAN DEFAULT FALSE COMMENT '是否已解锁详细资料',
    chat_message_count INT DEFAULT 0 COMMENT '聊天消息计数',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (matched_user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE KEY unique_match (user_id, matched_user_id),
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 聊天消息表
CREATE TABLE IF NOT EXISTS chat_messages (
    id INT AUTO_INCREMENT PRIMARY KEY,
    match_id INT NOT NULL,
    sender_id INT NOT NULL COMMENT '发送者用户ID',
    message TEXT NOT NULL,
    message_type ENUM('text', 'emoji', 'system') DEFAULT 'text',
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (match_id) REFERENCES matches(id) ON DELETE CASCADE,
    FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_match_id (match_id),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 评分记录表
CREATE TABLE IF NOT EXISTS ratings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    match_id INT NOT NULL,
    rater_id INT NOT NULL COMMENT '评分者ID',
    rated_user_id INT NOT NULL COMMENT '被评分者ID',
    score INT NOT NULL CHECK (score >= 1 AND score <= 5),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (match_id) REFERENCES matches(id) ON DELETE CASCADE,
    FOREIGN KEY (rater_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (rated_user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE KEY unique_match_rater (match_id, rater_id),
    INDEX idx_match_id (match_id),
    INDEX idx_rated_user (rated_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 购买记录表
CREATE TABLE IF NOT EXISTS purchases (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    matches_added INT NOT NULL COMMENT '增加的匹配次数',
    amount DECIMAL(10, 2) NOT NULL COMMENT '金额',
    currency VARCHAR(10) DEFAULT 'CNY',
    payment_method VARCHAR(50) DEFAULT 'iap_apple',
    transaction_id VARCHAR(100) DEFAULT NULL COMMENT '交易ID',
    status ENUM('pending', 'completed', 'failed', 'refunded') DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_id (user_id),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 系统代码表 (为每个匹配生成的匿名代码)
CREATE TABLE IF NOT EXISTS match_codes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    code VARCHAR(10) NOT NULL COMMENT '如 #A7F3C2',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE KEY unique_code (code),
    INDEX idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 插入66道问卷题目
INSERT INTO questions (id, text_cn, text_en, section, question_type, is_sensitive, weight) VALUES
-- 第一部分: 核心价值观 (1-15题)
(1, '诚实永远是上策,即使会伤害感情', 'Honesty is always the best policy, even if it hurts feelings', 'core_values', 'likert_7', FALSE, 1.5),
(2, '有些事情就是非黑即白的,没有灰色地带', 'Some things are just black and white, no gray areas', 'core_values', 'likert_7', FALSE, 1.0),
(3, '保护他人的感受比说真话更重要', 'Protecting others'' feelings is more important than telling the truth', 'core_values', 'likert_7', FALSE, 1.0),
(4, '个人成就比家庭时间更重要', 'Personal achievement is more important than family time', 'core_values', 'likert_7', FALSE, 1.5),
(5, '传统道德观念已经过时了', 'Traditional moral values are outdated', 'core_values', 'likert_7', FALSE, 1.0),
(6, '金钱是衡量成功的主要标准', 'Money is the main measure of success', 'core_values', 'likert_7', FALSE, 1.0),
(7, '宗教在我的生活中扮演重要角色', 'Religion plays an important role in my life', 'core_values', 'likert_7', FALSE, 1.5),
(8, '个人自由比社会秩序更重要', 'Personal freedom is more important than social order', 'core_values', 'likert_7', FALSE, 1.0),
(9, '我对伴侣的政治立场非常在意', 'I care very much about my partner''s political stance', 'core_values', 'likert_7', FALSE, 1.5),
(10, '我相信命运和缘分', 'I believe in fate and destiny', 'core_values', 'likert_7', FALSE, 1.0),
(11, '我认为个人应该为社会做贡献', 'I think individuals should contribute to society', 'core_values', 'likert_7', FALSE, 1.0),
(12, '我会为了正义而打破规则', 'I would break rules for justice', 'core_values', 'likert_7', FALSE, 1.0),
(13, '我认为有绝对的对错之分', 'I believe there is absolute right and wrong', 'core_values', 'likert_7', FALSE, 1.0),
(14, '个人成长比稳定更重要', 'Personal growth is more important than stability', 'core_values', 'likert_7', FALSE, 1.0),
(15, '我相信人是可以根本性改变的', 'I believe people can fundamentally change', 'core_values', 'likert_7', FALSE, 1.0),

-- 第二部分: 生活方式 (16-27题)
(16, '我更喜欢宅在家而不是社交', 'I prefer staying at home rather than socializing', 'lifestyle', 'likert_7', FALSE, 1.0),
(17, '我喜欢提前计划一切', 'I like to plan everything in advance', 'lifestyle', 'likert_7', FALSE, 1.0),
(18, '我需要大量的独处时间', 'I need a lot of alone time', 'lifestyle', 'likert_7', FALSE, 1.0),
(19, '我喜欢尝试新事物和冒险', 'I like trying new things and taking risks', 'lifestyle', 'likert_7', FALSE, 1.0),
(20, '我的生活很有规律', 'My life is very routine', 'lifestyle', 'likert_7', FALSE, 1.0),
(21, '健身和运动是我生活的重要组成部分', 'Fitness and exercise are an important part of my life', 'lifestyle', 'likert_7', FALSE, 1.0),
(22, '我可以接受伴侣偶尔使用软性毒品(大麻等)', 'I can accept my partner occasionally using soft drugs (marijuana, etc.)', 'lifestyle', 'likert_7', TRUE, 1.5),
(23, '我可以接受伴侣使用硬性毒品', 'I can accept my partner using hard drugs', 'lifestyle', 'likert_7', TRUE, 1.5),
(24, '我经常熬夜', 'I often stay up late', 'lifestyle', 'likert_7', FALSE, 1.0),
(25, '我喜欢举办聚会和邀请朋友来家里', 'I like hosting parties and inviting friends to my home', 'lifestyle', 'likert_7', FALSE, 1.0),
(26, '我花费大量时间在社交媒体上', 'I spend a lot of time on social media', 'lifestyle', 'likert_7', FALSE, 1.0),
(27, '我对整洁的要求很高', 'I have high requirements for cleanliness', 'lifestyle', 'likert_7', FALSE, 1.0),

-- 第三部分: 政治观点 (28-39题)
(28, '堕胎应该在任何情况下都合法', 'Abortion should be legal in all cases', 'political', 'likert_7', TRUE, 1.5),
(29, '政府应该提供全民医疗保健', 'Government should provide universal healthcare', 'political', 'likert_7', FALSE, 1.0),
(30, '富人应该缴纳更高比例的税收', 'The rich should pay higher proportion of taxes', 'political', 'likert_7', FALSE, 1.0),
(31, '枪支管制应该更加严格', 'Gun control should be stricter', 'political', 'likert_7', FALSE, 1.0),
(32, '移民对这个国家有积极影响', 'Immigration has a positive impact on this country', 'political', 'likert_7', FALSE, 1.0),
(33, '气候变化是人类造成的紧急问题', 'Climate change is a human-caused urgent issue', 'political', 'likert_7', FALSE, 1.0),
(34, '警察系统需要重大改革', 'The police system needs major reform', 'political', 'likert_7', FALSE, 1.0),
(35, '我应该能够根据自己认同的性别使用任何浴室', 'I should be able to use any bathroom based on my gender identity', 'political', 'likert_7', TRUE, 1.5),
(36, '如果我的孩子是LGBTQ+,我会完全支持', 'If my child is LGBTQ+, I would fully support them', 'political', 'likert_7', TRUE, 1.5),
(37, '资本主义是造成社会不公的主要原因', 'Capitalism is the main cause of social injustice', 'political', 'likert_7', FALSE, 1.0),
(38, '我们应该优先考虑本国公民', 'We should prioritize our own citizens', 'political', 'likert_7', FALSE, 1.0),
(39, '我积极参与政治和社会活动', 'I actively participate in political and social activities', 'political', 'likert_7', FALSE, 1.0),

-- 第四部分: 关系期望 (40-51题)
(40, '我想要孩子', 'I want children', 'relationship', 'choice_5', FALSE, 1.5),
(41, '我认为婚姻是长期关系的必要条件', 'I think marriage is necessary for long-term relationships', 'relationship', 'likert_7', FALSE, 1.5),
(42, '我对开放式关系持开放态度', 'I am open to open relationships', 'relationship', 'likert_7', TRUE, 1.5),
(43, '我需要伴侣和我有共同的宗教信仰', 'I need my partner to share my religious beliefs', 'relationship', 'likert_7', FALSE, 1.0),
(44, '我可以在开始交往后很快发生性关系', 'I can have sex soon after starting dating', 'relationship', 'likert_7', TRUE, 1.5),
(45, '性生活在长期关系中非常重要', 'Sex life is very important in long-term relationships', 'relationship', 'likert_7', FALSE, 1.0),
(46, '我需要每天和伴侣联系', 'I need to contact my partner every day', 'relationship', 'likert_7', FALSE, 1.0),
(47, '我可以接受异地恋', 'I can accept long-distance relationships', 'relationship', 'likert_7', FALSE, 1.5),
(48, '我希望伴侣和我有相似的收入水平', 'I hope my partner has a similar income level to me', 'relationship', 'likert_7', FALSE, 1.0),
(49, '我会和伴侣分享所有财务', 'I will share all finances with my partner', 'relationship', 'likert_7', FALSE, 1.0),
(50, '我期望和伴侣的父母保持密切关系', 'I expect to maintain close relationship with my partner''s parents', 'relationship', 'likert_7', FALSE, 1.0),
(51, '我可以接受伴侣有很亲密的异性朋友', 'I can accept my partner having very close friends of the opposite sex', 'relationship', 'likert_7', FALSE, 1.0),

-- 第五部分: 性格特质 (52-59题)
(52, '我更喜欢逻辑分析而非情感决策', 'I prefer logical analysis over emotional decision-making', 'personality', 'likert_7', FALSE, 1.0),
(53, '我经常担心未来', 'I often worry about the future', 'personality', 'likert_7', FALSE, 1.0),
(54, '我很容易适应新环境', 'I adapt easily to new environments', 'personality', 'likert_7', FALSE, 1.0),
(55, '我喜欢成为关注的焦点', 'I like being the center of attention', 'personality', 'likert_7', FALSE, 1.0),
(56, '我对批评很敏感', 'I am sensitive to criticism', 'personality', 'likert_7', FALSE, 1.0),
(57, '我更喜欢主导而非跟随', 'I prefer leading rather than following', 'personality', 'likert_7', FALSE, 1.0),
(58, '我经常会冲动做决定', 'I often make impulsive decisions', 'personality', 'likert_7', FALSE, 1.0),
(59, '我对艺术和审美很敏感', 'I am sensitive to art and aesthetics', 'personality', 'likert_7', FALSE, 1.0),

-- 第六部分: 沟通模式 (60-66题)
(60, '冲突时我倾向于直接面对而非回避', 'When in conflict, I tend to face it directly rather than avoid it', 'communication', 'likert_7', FALSE, 1.0),
(61, '我需要很多时间来处理情绪', 'I need a lot of time to process emotions', 'communication', 'likert_7', FALSE, 1.0),
(62, '我经常压抑自己的感受以避免冲突', 'I often suppress my feelings to avoid conflict', 'communication', 'likert_7', FALSE, 1.0),
(63, '我喜欢深入讨论抽象概念', 'I like deep discussions about abstract concepts', 'communication', 'likert_7', FALSE, 1.0),
(64, '我经常使用幽默来缓解紧张', 'I often use humor to relieve tension', 'communication', 'likert_7', FALSE, 1.0),
(65, '我觉得表达情感很困难', 'I find it difficult to express emotions', 'communication', 'likert_7', FALSE, 1.0),
(66, '我需要伴侣经常给我确认和肯定', 'I need my partner to frequently give me confirmation and affirmation', 'communication', 'likert_7', FALSE, 1.0);
