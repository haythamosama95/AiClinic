/// Invoice status aligned with PostgreSQL `invoice_status` enum (V1-6).
enum InvoiceStatus {
  draft,
  issued,
  partiallyPaid,
  paid,
  voided;

  static InvoiceStatus? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return switch (normalized) {
      'draft' => InvoiceStatus.draft,
      'issued' => InvoiceStatus.issued,
      'partially_paid' => InvoiceStatus.partiallyPaid,
      'paid' => InvoiceStatus.paid,
      'voided' => InvoiceStatus.voided,
      _ => null,
    };
  }

  String get wireValue => switch (this) {
    InvoiceStatus.draft => 'draft',
    InvoiceStatus.issued => 'issued',
    InvoiceStatus.partiallyPaid => 'partially_paid',
    InvoiceStatus.paid => 'paid',
    InvoiceStatus.voided => 'voided',
  };

  String get label => switch (this) {
    InvoiceStatus.draft => 'Draft',
    InvoiceStatus.issued => 'Issued',
    InvoiceStatus.partiallyPaid => 'Partially paid',
    InvoiceStatus.paid => 'Paid',
    InvoiceStatus.voided => 'Voided',
  };

  bool get isDraft => this == InvoiceStatus.draft;

  bool get isVoided => this == InvoiceStatus.voided;

  bool get isVoidable => this == InvoiceStatus.issued || this == InvoiceStatus.partiallyPaid;

  bool get isTerminal => this == InvoiceStatus.paid || this == InvoiceStatus.voided;
}
