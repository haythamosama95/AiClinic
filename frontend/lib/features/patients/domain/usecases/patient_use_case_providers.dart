import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/usecases/search_patients.dart';
import 'package:ai_clinic/features/patients/domain/usecases/get_patient.dart';
import 'package:ai_clinic/features/patients/domain/usecases/check_duplicates.dart';
import 'package:ai_clinic/features/patients/domain/usecases/create_patient.dart';
import 'package:ai_clinic/features/patients/domain/usecases/update_patient.dart';
import 'package:ai_clinic/features/patients/domain/usecases/archive_patient.dart';

final searchPatientsUseCaseProvider = Provider((ref) => SearchPatients(ref.watch(patientRepositoryProvider)));
final getPatientUseCaseProvider = Provider((ref) => GetPatient(ref.watch(patientRepositoryProvider)));
final checkDuplicatesUseCaseProvider = Provider((ref) => CheckDuplicates(ref.watch(patientRepositoryProvider)));
final createPatientUseCaseProvider = Provider((ref) => CreatePatient(ref.watch(patientRepositoryProvider)));
final updatePatientUseCaseProvider = Provider((ref) => UpdatePatient(ref.watch(patientRepositoryProvider)));
final archivePatientUseCaseProvider = Provider((ref) => ArchivePatient(ref.watch(patientRepositoryProvider)));
