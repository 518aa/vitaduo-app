// VitaDuo 官网 JavaScript

// 语言配置
const translations = {
    en: {
        nav: {
            features: 'Features',
            science: 'Science',
            howItWorks: 'How It Works',
            download: 'Download',
            privacy: 'Privacy Policy'
        },
        hero: {
            title: 'Find Your Soulmate<br><span class="gradient-text">Based on Values</span>',
            subtitle: 'VitaDuo uses advanced AI algorithms with a 66-question values questionnaire to match you with truly compatible partners. Not by appearance, but by heart.',
            stats: {
                satisfaction: 'Match Satisfaction',
                matches: 'Successful Matches',
                rating: 'App Rating'
            },
            downloadiOS: 'Download on App Store',
            downloadAndroid: 'Get it on Google Play'
        },
        features: {
            title: 'Why Choose VitaDuo',
            subtitle: 'Redefining dating, starting from the heart',
            items: {
                values: {
                    title: 'Values-Based Matching',
                    desc: '66-question deep questionnaire, AI analyzes your core values to find truly like-minded partners'
                },
                anonymous: {
                    title: 'Anonymous Chat',
                    desc: 'Chat first, see photos later. After 20 messages, mutual rating unlocks real profiles'
                },
                ai: {
                    title: 'AI Smart Recommendations',
                    desc: 'Using cosine similarity and Jaccard distance algorithms for precise compatibility matching'
                },
                global: {
                    title: 'Cross-Border Matching',
                    desc: 'Break geographical barriers, built-in translation makes language no longer an obstacle'
                },
                privacy: {
                    title: 'Privacy Protection',
                    desc: 'Your profile is only visible after mutual approval, fully controlling privacy boundaries'
                },
                rating: {
                    title: 'Mutual Rating',
                    desc: 'Two-way rating system ensures quality, unlock contacts only when both rate 4+ stars'
                }
            }
        },
        howItWorks: {
            title: 'Three Steps to True Love',
            subtitle: 'Simple, Efficient, Sincere',
            step1: {
                title: 'Complete Questionnaire',
                desc: 'Answer 66 carefully designed value questions to help us understand the real you'
            },
            step2: {
                title: 'Smart Matching',
                desc: 'AI algorithm recommends most compatible partners, 3 free chances per week'
            },
            step3: {
                title: 'Anonymous Communication',
                desc: 'Chat anonymously first, unlock real profiles after mutual approval, start real dating'
            }
        },
        science: {
            title: 'Backed by Science',
            subtitle: 'Our matching algorithm is based on decades of relationship research',
            '1': {
                title: 'Stanford Marriage Pact',
                desc: 'Research shows that value alignment is the #1 predictor of long-term relationship success. Couples with shared values report 67% higher satisfaction.'
            },
            '2': {
                title: 'Value Alignment Theory',
                desc: 'Core values form the foundation of compatibility. Our 66-question assessment evaluates your deepest beliefs to find truly compatible partners.'
            },
            '3': {
                title: 'Similarity-Attraction Effect',
                desc: 'Psychological research confirms that shared attitudes and beliefs significantly increase attraction and relationship satisfaction.'
            },
            '4': {
                title: 'Big Five Personality Model',
                desc: 'We analyze Openness, Conscientiousness, Extraversion, Agreeableness, and Neuroticism to predict personality compatibility.'
            },
            '5': {
                title: 'Gottman Relationship Research',
                desc: "Dr. John Gottman's 40-year research shows that shared meaning and value alignment are crucial for relationship longevity."
            }
        },
        download: {
            title: 'Start Finding True Love Now',
            subtitle: 'Available on iOS and Android',
            iOS: 'Download iOS Version',
            android: 'Download Android Version'
        },
        footer: {
            tagline: 'Values-based intelligent matching dating app',
            product: 'Product',
            support: 'Support',
            features: 'Features',
            usage: 'How It Works',
            downloadApp: 'Download',
            privacy: 'Privacy Policy',
            contact: 'Contact Us',
            faq: 'FAQ',
            followUs: 'Follow Us',
            rights: 'Made with 💜 for finding true love'
        }
    },
    zh: {
        nav: {
            features: '功能特性',
            science: '科学依据',
            howItWorks: '如何使用',
            download: '下载应用',
            privacy: '隐私政策'
        },
        hero: {
            title: '找到真正的灵魂伴侣<br><span class="gradient-text">基于价值观</span>',
            subtitle: 'VitaDuo 使用先进的 AI 算法，通过 66 题价值观问卷，为你匹配真正契合的伴侣。不再看脸，看心。',
            stats: {
                satisfaction: '匹配满意度',
                matches: '成功匹配',
                rating: '应用评分'
            },
            downloadiOS: 'App Store 下载',
            downloadAndroid: 'Google Play 下载'
        },
        features: {
            title: '为什么选择 VitaDuo',
            subtitle: '重新定义约会，从心开始',
            items: {
                values: {
                    title: '价值观匹配',
                    desc: '66题深度问卷，AI分析你的核心价值观，找到真正志同道合的人'
                },
                anonymous: {
                    title: '匿名聊天',
                    desc: '先聊心，再看脸。20条消息后互相评价，双方满意才解锁真实资料'
                },
                ai: {
                    title: 'AI智能推荐',
                    desc: '使用余弦相似度和Jaccard距离算法，精准匹配最合适的伴侣'
                },
                global: {
                    title: '跨国匹配',
                    desc: '打破地理限制，内置翻译功能，让语言不再是障碍'
                },
                privacy: {
                    title: '隐私保护',
                    desc: '你的资料只有双方互相认可后才可见，完全掌控隐私边界'
                },
                rating: {
                    title: '双向评分',
                    desc: '互评系统确保质量，双方4星以上才解锁联系方式'
                }
            }
        },
        howItWorks: {
            title: '三步找到真爱',
            subtitle: '简单、高效、用心',
            step1: {
                title: '完成问卷',
                desc: '回答66个精心设计的价值观问题，帮助我们了解真实的你'
            },
            step2: {
                title: '智能匹配',
                desc: 'AI算法为你推荐匹配度最高的伴侣，每周3次免费机会'
            },
            step3: {
                title: '匿名交流',
                desc: '先匿名聊天，互相认可后解锁真实资料，开始真实交往'
            }
        },
        science: {
            title: '科学依据',
            subtitle: '我们的匹配算法基于数十年的关系研究',
            '1': {
                title: '斯坦福婚姻契约研究',
                desc: '研究表明，价值观对齐是长期关系成功的首要预测因素。拥有共同价值观的伴侣满意度高出67%。'
            },
            '2': {
                title: '价值观对齐理论',
                desc: '核心价值观是兼容性的基础。我们的66题评估深入分析您的核心信念，为您寻找真正契合的伴侣。'
            },
            '3': {
                title: '相似性吸引原则',
                desc: '心理学研究证实，共同的态度和信念显著提升吸引力与关系满意度。'
            },
            '4': {
                title: '大五人格模型',
                desc: '我们分析开放性、尽责性、外向性、宜人性和神经质，预测人格兼容性。'
            },
            '5': {
                title: '戈特曼关系研究',
                desc: '约翰·戈特曼博士40年的研究表明，共同的意义和价值观对关系长久至关重要。'
            }
        },
        download: {
            title: '立即开始寻找真爱',
            subtitle: 'iOS 和 Android 全平台支持',
            iOS: '扫码下载 iOS 版',
            android: '扫码下载 Android 版'
        },
        footer: {
            tagline: '基于价值观的智能匹配约会应用',
            product: '产品',
            support: '支持',
            features: '功能特性',
            usage: '如何使用',
            downloadApp: '下载应用',
            privacy: '隐私政策',
            contact: '联系我们',
            faq: '常见问题',
            followUs: '关注我们',
            rights: '用 💜 打造，只为遇见真爱'
        }
    }
};

// 当前语言
let currentLang = localStorage.getItem('language') || 'en';

// 初始化
document.addEventListener('DOMContentLoaded', () => {
    updateLanguage(currentLang);
    initMobileMenu();
    initLangToggle();
});

// 更新语言
function updateLanguage(lang) {
    console.log('updateLanguage called with:', lang);
    currentLang = lang;
    localStorage.setItem('language', lang);
    console.log('Language saved to localStorage:', lang);

    // 使用通用的更新函数，避免元素不存在时报错
    const updateText = (selector, text) => {
        const element = document.querySelector(selector);
        if (element) {
            element.textContent = text;
        }
    };

    const updateHTML = (selector, html) => {
        const element = document.querySelector(selector);
        if (element) {
            element.innerHTML = html;
        }
    };

    // 更新导航
    updateText('[data-i18n="nav.features"]', translations[lang].nav.features);
    updateText('[data-i18n="nav.science"]', translations[lang].nav.science);
    updateText('[data-i18n="nav.howItWorks"]', translations[lang].nav.howItWorks);
    updateText('[data-i18n="nav.download"]', translations[lang].nav.download);
    updateText('[data-i18n="nav.privacy"]', translations[lang].nav.privacy);

    // 更新英雄区域
    updateHTML('[data-i18n="hero.title"]', translations[lang].hero.title);
    updateText('[data-i18n="hero.subtitle"]', translations[lang].hero.subtitle);
    updateText('[data-i18n="hero.stat1"]', translations[lang].hero.stats.satisfaction);
    updateText('[data-i18n="hero.stat2"]', translations[lang].hero.stats.matches);
    updateText('[data-i18n="hero.stat3"]', translations[lang].hero.stats.rating);
    updateText('[data-i18n="hero.downloadiOS"]', translations[lang].hero.downloadiOS);
    updateText('[data-i18n="hero.downloadAndroid"]', translations[lang].hero.downloadAndroid);

    // 更新特性
    updateText('[data-i18n="features.title"]', translations[lang].features.title);
    updateText('[data-i18n="features.subtitle"]', translations[lang].features.subtitle);
    updateText('[data-i18n="features.1.title"]', translations[lang].features.items.values.title);
    updateText('[data-i18n="features.1.desc"]', translations[lang].features.items.values.desc);
    updateText('[data-i18n="features.2.title"]', translations[lang].features.items.anonymous.title);
    updateText('[data-i18n="features.2.desc"]', translations[lang].features.items.anonymous.desc);
    updateText('[data-i18n="features.3.title"]', translations[lang].features.items.ai.title);
    updateText('[data-i18n="features.3.desc"]', translations[lang].features.items.ai.desc);
    updateText('[data-i18n="features.4.title"]', translations[lang].features.items.global.title);
    updateText('[data-i18n="features.4.desc"]', translations[lang].features.items.global.desc);
    updateText('[data-i18n="features.5.title"]', translations[lang].features.items.privacy.title);
    updateText('[data-i18n="features.5.desc"]', translations[lang].features.items.privacy.desc);
    updateText('[data-i18n="features.6.title"]', translations[lang].features.items.rating.title);
    updateText('[data-i18n="features.6.desc"]', translations[lang].features.items.rating.desc);

    // 更新如何使用
    updateText('[data-i18n="how.title"]', translations[lang].howItWorks.title);
    updateText('[data-i18n="how.subtitle"]', translations[lang].howItWorks.subtitle);
    updateText('[data-i18n="how.step1.title"]', translations[lang].howItWorks.step1.title);
    updateText('[data-i18n="how.step1.desc"]', translations[lang].howItWorks.step1.desc);
    updateText('[data-i18n="how.step2.title"]', translations[lang].howItWorks.step2.title);
    updateText('[data-i18n="how.step2.desc"]', translations[lang].howItWorks.step2.desc);
    updateText('[data-i18n="how.step3.title"]', translations[lang].howItWorks.step3.title);
    updateText('[data-i18n="how.step3.desc"]', translations[lang].howItWorks.step3.desc);

    // 更新科学依据
    updateText('[data-i18n="science.title"]', translations[lang].science.title);
    updateText('[data-i18n="science.subtitle"]', translations[lang].science.subtitle);
    updateText('[data-i18n="science.1.title"]', translations[lang].science['1'].title);
    updateText('[data-i18n="science.1.desc"]', translations[lang].science['1'].desc);
    updateText('[data-i18n="science.2.title"]', translations[lang].science['2'].title);
    updateText('[data-i18n="science.2.desc"]', translations[lang].science['2'].desc);
    updateText('[data-i18n="science.3.title"]', translations[lang].science['3'].title);
    updateText('[data-i18n="science.3.desc"]', translations[lang].science['3'].desc);
    updateText('[data-i18n="science.4.title"]', translations[lang].science['4'].title);
    updateText('[data-i18n="science.4.desc"]', translations[lang].science['4'].desc);
    updateText('[data-i18n="science.5.title"]', translations[lang].science['5'].title);
    updateText('[data-i18n="science.5.desc"]', translations[lang].science['5'].desc);

    // 更新下载
    updateText('[data-i18n="download.title"]', translations[lang].download.title);
    updateText('[data-i18n="download.subtitle"]', translations[lang].download.subtitle);
    updateText('[data-i18n="download.ios"]', translations[lang].download.iOS);
    updateText('[data-i18n="download.android"]', translations[lang].download.android);

    // 更新页脚
    updateText('[data-i18n="footer.tagline"]', translations[lang].footer.tagline);
    updateText('[data-i18n="footer.product"]', translations[lang].footer.product);
    updateText('[data-i18n="footer.support"]', translations[lang].footer.support);
    updateText('[data-i18n="footer.features"]', translations[lang].footer.features);
    updateText('[data-i18n="footer.usage"]', translations[lang].footer.usage);
    updateText('[data-i18n="footer.download"]', translations[lang].footer.downloadApp);
    updateText('[data-i18n="footer.privacy"]', translations[lang].footer.privacy);
    updateText('[data-i18n="footer.contact"]', translations[lang].footer.contact);
    updateText('[data-i18n="footer.faq"]', translations[lang].footer.faq);
    updateText('[data-i18n="footer.follow"]', translations[lang].footer.followUs);
    updateText('[data-i18n="footer.rights"]', translations[lang].footer.rights);

    // 更新语言切换按钮
    updateLangToggle();
    console.log('Language update completed:', lang);
}

// 语言切换按钮
function initLangToggle() {
    const langToggle = document.getElementById('langToggle');
    if (langToggle) {
        langToggle.addEventListener('click', () => {
            console.log('Language toggle clicked. Current language:', currentLang);
            const newLang = currentLang === 'en' ? 'zh' : 'en';
            console.log('Switching to:', newLang);
            updateLanguage(newLang);
        });
        console.log('Language toggle button initialized');
    } else {
        console.warn('Language toggle button not found in DOM');
    }
}

function updateLangToggle() {
    const langToggle = document.getElementById('langToggle');
    if (langToggle) {
        langToggle.textContent = currentLang === 'en' ? '中文' : 'English';
    } else {
        console.warn('Language toggle button not found');
    }
}

// 移动端菜单
function initMobileMenu() {
    const navToggle = document.querySelector('.nav-toggle');
    const navMenu = document.querySelector('.nav-menu');

    if (navToggle && navMenu) {
        navToggle.addEventListener('click', () => {
            navMenu.classList.toggle('active');
        });

        // 点击菜单项后关闭菜单
        navMenu.querySelectorAll('.nav-link').forEach(link => {
            link.addEventListener('click', () => {
                navMenu.classList.remove('active');
            });
        });
    }
}

// 平滑滚动
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            target.scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
        }
    });
});

// 滚动时导航栏效果
let lastScroll = 0;
window.addEventListener('scroll', () => {
    const navbar = document.querySelector('.navbar');
    const currentScroll = window.pageYOffset;

    if (currentScroll > 100) {
        navbar.style.boxShadow = '0 4px 20px rgba(0, 0, 0, 0.1)';
    } else {
        navbar.style.boxShadow = '0 2px 10px rgba(0, 0, 0, 0.1)';
    }

    lastScroll = currentScroll;
});
