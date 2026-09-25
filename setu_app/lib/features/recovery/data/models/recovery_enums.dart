enum DamageCategory {
  building('Building'),
  road('Road'),
  electricity('Electricity'),
  water('Water'),
  fire('Fire'),
  other('Other');

  const DamageCategory(this.label);
  final String label;
}

enum DamageSeverity {
  low('Low'),
  medium('Medium'),
  high('High'),
  critical('Critical');

  const DamageSeverity(this.label);
  final String label;
}

enum ResourceType {
  food('Food'),
  water('Water'),
  medical('Medical assistance'),
  shelter('Shelter'),
  rescue('Rescue'),
  other('Other');

  const ResourceType(this.label);
  final String label;
}

enum RequestUrgency {
  normal('Normal'),
  urgent('Urgent'),
  critical('Critical');

  const RequestUrgency(this.label);
  final String label;
}
