# Egyptian Investigations Catalog — كتالوج التحاليل والفحوصات الشائعة في مصر

> **135 commonly ordered investigations** used in Egyptian outpatient clinics, national lab checkup packages, and routine الفحص الشامل panels.
>
> **135 فحصًا وتحليلًا شائعًا** في العيادات المصرية وباقات المختبرات الوطنية والفحص الشامل.

![records](https://img.shields.io/badge/records-135-2ea44f)
![updated](https://img.shields.io/badge/updated-June%202026-blue)
![format](https://img.shields.io/badge/format-JSON-orange)

---

## What this is — ما هي هذه القاعدة

A curated, machine-readable list of laboratory tests, imaging studies, and diagnostic procedures commonly ordered by doctors in Egypt. Names follow what appears on Egyptian lab reports and prescriptions (English clinical terms with Arabic aliases for search).

قائمة منسقة وقابلة للقراءة آليًا بأهم التحاليل والأشعة والفحوصات التي يطلبها الأطباء في مصر. الأسماء الإنجليزية تطابق ما يظهر في تقارير المختبرات والروشتات، مع أسماء عربية للبحث.

**Last updated:** June 2026 — **آخر تحديث:** يونيو 2026

---

## Schema — البنية

| column | type | description (EN) | الوصف (AR) |
|---|---|---|---|
| `name_en` | string | Stored in `investigations.name` (max 200 chars) | الاسم الإنجليزي في قاعدة البيانات |
| `name_ar` | string | Arabic name for display / future search | الاسم العربي |
| `category` | string | Clinical grouping | التصنيف السريري |
| `aliases` | string[] | Abbreviations and alternate terms | اختصارات وأسماء بديلة |

---

## Sources — المصادر

Curated from Egyptian lab checkup packages and clinical guides:

- AlFarabi Medical Labs — Spring Basic Package (باقة الربيع الأساسية)
- Nilescan and Labs — Comprehensive Checkup (الفحص الشامل)
- European Medical Center — Full Checkup Guide
- Dalili Medical — Essential Blood Tests Guide
- AiClinic `docs/reference/medical-investigations-catalog.md` (international cross-check)

---

## Files — الملفات

```
data/egyptian-investigations/
├── SOURCE.md
├── egyptian-investigations.json          # Full records with Arabic names and categories
└── investigation_catalog_names.json      # name_en values only (for DB seeding)

frontend/assets/dev/
└── egyptian_investigation_names.json     # Bundled copy for Fill Dummy Clinic
```

For AiClinic dev seeding, `investigation_catalog_names.json` contains only the `name_en` values formatted for the `investigations.name` column (unique per organization, max 200 characters). The Flutter app bundles a copy at `frontend/assets/dev/egyptian_investigation_names.json`.

---

## Dev seeding — تعبئة بيانات العيادة التجريبية

Fill Dummy Clinic imports all names via `dev_seed_investigations_catalog` (bootstrap admin, dev environments only), mirroring the Egyptian medications import flow.

---

## Categories — التصنيفات

| category | examples |
|---|---|
| `haematology` | CBC, ESR, coagulation |
| `biochemistry` | LFT, KFT, lipids, glucose, electrolytes |
| `endocrine` | TSH, TFT, hormones |
| `urine_studies` | Urinalysis, microalbumin |
| `stool_studies` | Stool analysis, occult blood |
| `microbiology` | Blood/urine/stool culture |
| `virology_serology` | HBsAg, Anti-HCV, HIV, TORCH |
| `molecular` | COVID-19 PCR, influenza PCR |
| `immunology` | CRP, ANA, RF |
| `imaging_radiology` | X-ray, ultrasound, CT, MRI |
| `cardiology` | ECG, echo, troponin |
| `pulmonary` | Spirometry |
| `gastroenterology` | Endoscopy, colonoscopy |
| `neurology` | EEG, EMG, lumbar puncture |
| `obstetrics_gynaecology` | Pap smear, HPV, semen analysis |
| `urology` | Uroflowmetry, cystoscopy |
| `pathology` | Biopsy, FNA |

---

## Regenerating the names bundle

If you edit `egyptian-investigations.json`, sync the seed bundle:

```bash
python3 - <<'PY'
import json
from pathlib import Path

src = Path('data/egyptian-investigations/egyptian-investigations.json')
data = json.loads(src.read_text())
names = [row['name_en'] for row in data['investigations']]
bundle = {
    'source': 'data/egyptian-investigations/egyptian-investigations.json',
    'field': 'name_en',
    'count': len(names),
    'names': names,
}
for path in [
    Path('data/egyptian-investigations/investigation_catalog_names.json'),
    Path('frontend/assets/dev/egyptian_investigation_names.json'),
]:
    path.write_text(json.dumps(bundle, indent=2, ensure_ascii=False) + '\n')
print(f'Synced {len(names)} investigation names')
PY
```
