import type { EncounterWorkspace } from "./encounter-types";

function atToday(hour: number, minute = 0): string {
  const d = new Date();
  d.setHours(hour, minute, 0, 0);
  return d.toISOString();
}

function daysAgo(days: number, hour = 10): string {
  const d = new Date();
  d.setDate(d.getDate() - days);
  d.setHours(hour, 0, 0, 0);
  return d.toISOString();
}

export const encounterWorkspace: EncounterWorkspace = {
  visit: {
    id: "v-2847",
    dateTime: atToday(9, 15),
    status: "in_progress",
    type: "General consultation",
    branch: "Main clinic",
  },
  patient: {
    name: "Youssef Nader",
    age: 42,
    sex: "Male",
    mrn: "MRN-10842",
    dateOfBirth: "1983-11-04",
    phone: "+20 100 234 5678",
  },
  doctor: {
    name: "Dr. Sara Mansour",
    specialty: "Internal medicine",
  },
  safety: {
    allergies: [
      { substance: "Penicillin", reaction: "Rash, urticaria" },
      { substance: "Sulfa drugs", reaction: "Nausea" },
    ],
    currentMedications: [
      "Metformin 500 mg — twice daily",
      "Lisinopril 10 mg — once daily",
      "Atorvastatin 20 mg — at bedtime",
    ],
    chronicConditions: ["Type 2 diabetes", "Hypertension", "Hyperlipidemia"],
    lastVitals: [
      { type: "Blood pressure", value: "138/88", unit: "mmHg", measuredAt: daysAgo(14) },
      { type: "Weight", value: "92", unit: "kg", measuredAt: daysAgo(14) },
      { type: "Heart rate", value: "78", unit: "bpm", measuredAt: daysAgo(14) },
    ],
  },
  note: {
    complaint:
      "Persistent dry cough for 10 days, worse at night. Mild sore throat. No fever reported.",
    history:
      "Non-smoker. No recent travel. Diabetes and hypertension well controlled on current meds. Last HbA1c 7.1% (3 months ago). No known sick contacts.",
    examination:
      "Alert, no distress. Temp 37.2°C. Oropharynx mildly erythematous, no exudate. Lungs: scattered rhonchi bilaterally, no wheeze. Heart regular. No peripheral edema.",
    diagnosis:
      "Acute bronchitis, likely viral. Type 2 diabetes mellitus — stable. Essential hypertension — stable.",
    plan:
      "Symptomatic care: fluids, rest, honey for cough. Return if fever >38.5°C, dyspnea, or symptoms >3 weeks. Continue home medications. Follow-up in 2 weeks or sooner if worsening.",
  },
  vitals: [
    { type: "Temperature", value: "37.2", unit: "°C", measuredAt: atToday(9, 18) },
    { type: "Blood pressure", value: "132/84", unit: "mmHg", measuredAt: atToday(9, 18) },
    { type: "Heart rate", value: "76", unit: "bpm", measuredAt: atToday(9, 18) },
    { type: "Respiratory rate", value: "18", unit: "/min", measuredAt: atToday(9, 18) },
    { type: "SpO₂", value: "97", unit: "%", measuredAt: atToday(9, 18) },
    { type: "Weight", value: "91.5", unit: "kg", measuredAt: atToday(9, 18) },
    { type: "Height", value: "178", unit: "cm", measuredAt: atToday(9, 18) },
  ],
  treatments: [
    {
      id: "t1",
      medication: "Guaifenesin",
      dose: "400 mg",
      frequency: "Every 8 hours",
      duration: "7 days",
      instructions: "Take with water after meals",
    },
    {
      id: "t2",
      medication: "Paracetamol",
      dose: "500 mg",
      frequency: "As needed",
      duration: "5 days",
      instructions: "Max 4 g per day. For throat discomfort or low-grade fever",
    },
  ],
  investigations: [
    {
      id: "i1",
      name: "Complete blood count",
      status: "ordered",
      orderedAt: atToday(9, 25),
    },
    {
      id: "i2",
      name: "Chest X-ray",
      status: "pending",
      orderedAt: atToday(9, 25),
    },
    {
      id: "i3",
      name: "HbA1c",
      status: "completed",
      orderedAt: daysAgo(90),
      result: "7.1%",
      resultRecordedAt: daysAgo(88),
    },
  ],
  attachments: [
    {
      id: "a1",
      name: "Previous lab results — March 2026.pdf",
      fileType: "PDF",
      uploadedAt: daysAgo(2),
      sizeLabel: "248 KB",
    },
    {
      id: "a2",
      name: "Chest X-ray referral form.pdf",
      fileType: "PDF",
      uploadedAt: atToday(9, 26),
      sizeLabel: "112 KB",
    },
    {
      id: "a3",
      name: "ECG strip — prior visit.png",
      fileType: "Image",
      uploadedAt: daysAgo(120),
      sizeLabel: "1.2 MB",
    },
  ],
};

export const emptyEncounterWorkspace: EncounterWorkspace = {
  visit: {
    id: "v-empty",
    dateTime: atToday(10, 0),
    status: "scheduled",
    type: "New patient",
    branch: "Main clinic",
  },
  patient: {
    name: "New Patient",
    age: 0,
    sex: "—",
    mrn: "—",
    dateOfBirth: "—",
  },
  doctor: { name: "—", specialty: "—" },
  safety: {
    allergies: [],
    currentMedications: [],
    chronicConditions: [],
    lastVitals: [],
  },
  note: {
    complaint: "",
    history: "",
    examination: "",
    diagnosis: "",
    plan: "",
  },
  vitals: [],
  treatments: [],
  investigations: [],
  attachments: [],
};
