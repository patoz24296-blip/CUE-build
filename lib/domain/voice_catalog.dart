class PartnerVoice {
  const PartnerVoice(this.id, this.name, this.description, this.language);
  final int id;
  final String name, description, language;
  int get speaker => 1000 + id;
  String get label => '$name · $description';
}

const partnerVoices = [
  PartnerVoice(3, 'Heart', 'American · female · warm', 'en'),
  PartnerVoice(2, 'Bella', 'American · female · clear', 'en'),
  PartnerVoice(6, 'Nicole', 'American · female · soft', 'en'),
  PartnerVoice(9, 'Sarah', 'American · female · grounded', 'en'),
  PartnerVoice(17, 'Onyx', 'American · male · deep', 'en'),
  PartnerVoice(16, 'Michael', 'American · male · clear', 'en'),
  PartnerVoice(18, 'Puck', 'American · male · bright', 'en'),
  PartnerVoice(15, 'Liam', 'American · male', 'en'),
  PartnerVoice(21, 'Emma', 'British · female', 'en'),
  PartnerVoice(22, 'Isabella', 'British · female', 'en'),
  PartnerVoice(24, 'Daniel', 'British · male', 'en'),
  PartnerVoice(26, 'George', 'British · male', 'en'),
  PartnerVoice(28, 'Dora', 'Spanish · female', 'es'),
  PartnerVoice(29, 'Alex', 'Spanish · male', 'es'),
  PartnerVoice(53, 'Santa', 'Spanish · male', 'es'),
];

PartnerVoice suggestedVoice(
  String character,
  int index, {
  String language = 'en',
}) {
  final choices = partnerVoices.where((v) => v.language == language).toList();
  final name = character.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  final female = {
    'mara',
    'anna',
    'mary',
    'jane',
    'juliet',
    'cecily',
    'gwendolen',
    'sarah',
    'emma',
    'alice',
    'mother',
    'mom',
    'wife',
    'daughter',
  };
  final male = {
    'leo',
    'theo',
    'thomas',
    'david',
    'michael',
    'daniel',
    'ben',
    'max',
    'john',
    'jack',
    'james',
    'algernon',
    'hamlet',
    'romeo',
    'father',
    'dad',
    'husband',
    'son',
  };
  final matching = choices
      .where(
        (v) => female.contains(name)
            ? v.description.contains('female')
            : male.contains(name)
            ? !v.description.contains('female')
            : index.isEven
            ? v.description.contains('female')
            : !v.description.contains('female'),
      )
      .toList();
  return matching[index.abs() % matching.length];
}

PartnerVoice resolveVoice(
  int speaker,
  String character,
  int index, {
  String language = 'en',
}) =>
    partnerVoices
        .where((v) => v.speaker == speaker && v.language == language)
        .firstOrNull ??
    suggestedVoice(character, index, language: language);
