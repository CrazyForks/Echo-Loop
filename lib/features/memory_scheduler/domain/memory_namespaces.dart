/// 记忆调度使用的业务内容命名空间。
library;

/// 收藏句子的调度命名空间。
const kSavedSentenceNamespace = 'saved_sentence';

/// 单词及普通查词/手动选择收藏的多词表达命名空间。
const kSavedWordOrPhraseNamespace = 'saved_word_or_phrase';

/// 通过意群入口收藏的语义片段命名空间。
const kSavedSenseGroupNamespace = 'saved_sense_group';

/// 全部收藏内容的调度命名空间。
const kSavedContentNamespaces = <String>[
  kSavedSentenceNamespace,
  kSavedWordOrPhraseNamespace,
  kSavedSenseGroupNamespace,
];

/// 收藏词汇复习共用每日预算的命名空间。
const kSavedWordAndSenseGroupNamespaces = <String>[
  kSavedWordOrPhraseNamespace,
  kSavedSenseGroupNamespace,
];
