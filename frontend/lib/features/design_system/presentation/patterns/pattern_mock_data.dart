// Mock rows for pattern demos (web `mock-data.ts`).

class PatternServiceRow {
  const PatternServiceRow({
    required this.id,
    required this.name,
    required this.category,
    required this.defaultPrice,
    required this.status,
    required this.branches,
  });

  final String id;
  final String name;
  final String category;
  final double defaultPrice;
  final String status;
  final int branches;
}

const kPatternMockServices = <PatternServiceRow>[
  PatternServiceRow(
    id: 's1',
    name: 'General consultation',
    category: 'Consultation',
    defaultPrice: 350,
    status: 'active',
    branches: 3,
  ),
  PatternServiceRow(
    id: 's2',
    name: 'Dental cleaning',
    category: 'Dental',
    defaultPrice: 500,
    status: 'active',
    branches: 2,
  ),
  PatternServiceRow(
    id: 's3',
    name: 'Blood panel (CBC)',
    category: 'Lab',
    defaultPrice: 180,
    status: 'active',
    branches: 3,
  ),
  PatternServiceRow(
    id: 's4',
    name: 'X-ray (chest)',
    category: 'Imaging',
    defaultPrice: 220,
    status: 'inactive',
    branches: 1,
  ),
  PatternServiceRow(
    id: 's5',
    name: 'Physiotherapy session',
    category: 'Therapy',
    defaultPrice: 400,
    status: 'active',
    branches: 2,
  ),
  PatternServiceRow(
    id: 's6',
    name: 'Vaccination (flu)',
    category: 'Preventive',
    defaultPrice: 150,
    status: 'active',
    branches: 3,
  ),
  PatternServiceRow(id: 's7', name: 'ECG', category: 'Cardiology', defaultPrice: 275, status: 'active', branches: 2),
  PatternServiceRow(
    id: 's8',
    name: 'Ultrasound (abdominal)',
    category: 'Imaging',
    defaultPrice: 650,
    status: 'active',
    branches: 2,
  ),
];
