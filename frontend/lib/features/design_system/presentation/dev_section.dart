/// Design system dev page sections (web `DevSection`).
enum DevSection { foundations, components, patterns, guidelines }

extension DevSectionId on DevSection {
  String get id => switch (this) {
    DevSection.foundations => 'foundations',
    DevSection.components => 'components',
    DevSection.patterns => 'patterns',
    DevSection.guidelines => 'guidelines',
  };

  String get label => switch (this) {
    DevSection.foundations => 'Foundations',
    DevSection.components => 'Components',
    DevSection.patterns => 'Patterns',
    DevSection.guidelines => 'Guidelines',
  };

  static DevSection fromId(String id) => DevSection.values.firstWhere(
    (section) => section.id == id,
    orElse: () => DevSection.foundations,
  );
}
