// Web parity: settings.ts exports use SCREAMING_SNAKE_CASE constant names.
// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';

/// Select option used by timezone, currency, and staff role pickers.
@immutable
class SelectOption {
  const SelectOption({required this.value, required this.label});

  final String value;
  final String label;
}

/// Metadata for a day-of-week row in the working-hours editor.
@immutable
class DayOfWeekMeta {
  const DayOfWeekMeta({required this.id, required this.label, required this.short});

  final String id;
  final String label;
  final String short;
}

typedef DayId = String;

const List<SelectOption> timezoneOptions = [
  SelectOption(value: 'Africa/Cairo', label: 'Cairo (GMT+2)'),
  SelectOption(value: 'Asia/Riyadh', label: 'Riyadh (GMT+3)'),
  SelectOption(value: 'Asia/Dubai', label: 'Dubai (GMT+4)'),
  SelectOption(value: 'Europe/London', label: 'London (GMT+0)'),
  SelectOption(value: 'Europe/Berlin', label: 'Berlin (GMT+1)'),
  SelectOption(value: 'America/New_York', label: 'New York (GMT-5)'),
];

/// Web export name: `TIMEZONE_OPTIONS`.
const List<SelectOption> TIMEZONE_OPTIONS = timezoneOptions;

const List<SelectOption> currencyOptions = [
  SelectOption(value: 'EGP', label: 'Egyptian Pound (EGP)'),
  SelectOption(value: 'SAR', label: 'Saudi Riyal (SAR)'),
  SelectOption(value: 'AED', label: 'UAE Dirham (AED)'),
  SelectOption(value: 'USD', label: 'US Dollar (USD)'),
  SelectOption(value: 'EUR', label: 'Euro (EUR)'),
  SelectOption(value: 'GBP', label: 'British Pound (GBP)'),
];

/// Web export name: `CURRENCY_OPTIONS`.
const List<SelectOption> CURRENCY_OPTIONS = currencyOptions;

const List<SelectOption> staffRoleOptions = [
  SelectOption(value: 'administrator', label: 'Administrator'),
  SelectOption(value: 'doctor', label: 'Doctor'),
  SelectOption(value: 'receptionist', label: 'Receptionist'),
  SelectOption(value: 'lab_staff', label: 'Lab staff'),
];

/// Web export name: `STAFF_ROLE_OPTIONS`.
const List<SelectOption> STAFF_ROLE_OPTIONS = staffRoleOptions;

const List<DayOfWeekMeta> daysOfWeek = [
  DayOfWeekMeta(id: 'mon', label: 'Monday', short: 'Mon'),
  DayOfWeekMeta(id: 'tue', label: 'Tuesday', short: 'Tue'),
  DayOfWeekMeta(id: 'wed', label: 'Wednesday', short: 'Wed'),
  DayOfWeekMeta(id: 'thu', label: 'Thursday', short: 'Thu'),
  DayOfWeekMeta(id: 'fri', label: 'Friday', short: 'Fri'),
  DayOfWeekMeta(id: 'sat', label: 'Saturday', short: 'Sat'),
  DayOfWeekMeta(id: 'sun', label: 'Sunday', short: 'Sun'),
];

/// Web export name: `DAYS_OF_WEEK`.
const List<DayOfWeekMeta> DAYS_OF_WEEK = daysOfWeek;

@immutable
class WorkingDay {
  const WorkingDay({required this.day, required this.enabled, required this.openTime, required this.closeTime});

  final DayId day;
  final bool enabled;
  final String openTime;
  final String closeTime;

  WorkingDay copyWith({DayId? day, bool? enabled, String? openTime, String? closeTime}) {
    return WorkingDay(
      day: day ?? this.day,
      enabled: enabled ?? this.enabled,
      openTime: openTime ?? this.openTime,
      closeTime: closeTime ?? this.closeTime,
    );
  }

  Map<String, dynamic> toJson() => {'day': day, 'enabled': enabled, 'openTime': openTime, 'closeTime': closeTime};

  factory WorkingDay.fromJson(Map<String, dynamic> json) {
    return WorkingDay(
      day: json['day'] as String,
      enabled: json['enabled'] as bool? ?? false,
      openTime: json['openTime'] as String? ?? '09:00',
      closeTime: json['closeTime'] as String? ?? '17:00',
    );
  }
}

@immutable
class BranchDraft {
  const BranchDraft({
    required this.id,
    required this.name,
    required this.code,
    required this.mobile,
    required this.mapLocation,
    required this.workingDays,
  });

  final String id;
  final String name;
  final String code;
  final String mobile;
  final String mapLocation;
  final List<WorkingDay> workingDays;

  BranchDraft copyWith({
    String? id,
    String? name,
    String? code,
    String? mobile,
    String? mapLocation,
    List<WorkingDay>? workingDays,
  }) {
    return BranchDraft(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      mobile: mobile ?? this.mobile,
      mapLocation: mapLocation ?? this.mapLocation,
      workingDays: workingDays ?? this.workingDays,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'code': code,
    'mobile': mobile,
    'mapLocation': mapLocation,
    'workingDays': workingDays.map((day) => day.toJson()).toList(),
  };

  factory BranchDraft.fromJson(Map<String, dynamic> json) {
    final rawDays = json['workingDays'] as List<dynamic>?;
    return BranchDraft(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      mobile: json['mobile'] as String? ?? '',
      mapLocation: json['mapLocation'] as String? ?? '',
      workingDays: rawDays == null
          ? createDefaultWorkingDays()
          : rawDays.map((day) => WorkingDay.fromJson(day as Map<String, dynamic>)).toList(),
    );
  }
}

@immutable
class StaffDraft {
  const StaffDraft({
    required this.id,
    required this.name,
    required this.mobile,
    required this.username,
    required this.password,
    required this.role,
    required this.branchIds,
  });

  final String id;
  final String name;
  final String mobile;
  final String username;
  final String password;
  final String role;
  final List<String> branchIds;

  StaffDraft copyWith({
    String? id,
    String? name,
    String? mobile,
    String? username,
    String? password,
    String? role,
    List<String>? branchIds,
  }) {
    return StaffDraft(
      id: id ?? this.id,
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      username: username ?? this.username,
      password: password ?? this.password,
      role: role ?? this.role,
      branchIds: branchIds ?? this.branchIds,
    );
  }

  /// Passwords are collected transiently in the UI and must not be persisted.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mobile': mobile,
    'username': username,
    'role': role,
    'branchIds': branchIds,
  };

  factory StaffDraft.fromJson(Map<String, dynamic> json) {
    final rawBranchIds = json['branchIds'] as List<dynamic>?;
    return StaffDraft(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      mobile: json['mobile'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      role: json['role'] as String? ?? '',
      branchIds: rawBranchIds?.map((id) => id as String).toList() ?? const [],
    );
  }
}

@immutable
class ServiceDraft {
  const ServiceDraft({required this.id, required this.name, required this.price});

  final String id;
  final String name;
  final double? price;

  ServiceDraft copyWith({String? id, String? name, double? price, bool clearPrice = false}) {
    return ServiceDraft(id: id ?? this.id, name: name ?? this.name, price: clearPrice ? null : (price ?? this.price));
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'price': price};

  factory ServiceDraft.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['price'];
    return ServiceDraft(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      price: rawPrice == null ? null : (rawPrice as num).toDouble(),
    );
  }
}

@immutable
class OrganizationDraft {
  const OrganizationDraft({required this.name, required this.timezone, required this.currency});

  final String name;
  final String timezone;
  final String currency;

  OrganizationDraft copyWith({String? name, String? timezone, String? currency}) {
    return OrganizationDraft(
      name: name ?? this.name,
      timezone: timezone ?? this.timezone,
      currency: currency ?? this.currency,
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'timezone': timezone, 'currency': currency};

  factory OrganizationDraft.fromJson(Map<String, dynamic> json) {
    return OrganizationDraft(
      name: json['name'] as String? ?? '',
      timezone: json['timezone'] as String? ?? 'Africa/Cairo',
      currency: json['currency'] as String? ?? 'EGP',
    );
  }
}

@immutable
class SetupDraft {
  const SetupDraft({required this.organization, required this.branches, required this.staff, required this.services});

  final OrganizationDraft organization;
  final List<BranchDraft> branches;
  final List<StaffDraft> staff;
  final List<ServiceDraft> services;

  SetupDraft copyWith({
    OrganizationDraft? organization,
    List<BranchDraft>? branches,
    List<StaffDraft>? staff,
    List<ServiceDraft>? services,
  }) {
    return SetupDraft(
      organization: organization ?? this.organization,
      branches: branches ?? this.branches,
      staff: staff ?? this.staff,
      services: services ?? this.services,
    );
  }

  Map<String, dynamic> toJson() => {
    'organization': organization.toJson(),
    'branches': branches.map((branch) => branch.toJson()).toList(),
    'staff': staff.map((member) => member.toJson()).toList(),
    'services': services.map((service) => service.toJson()).toList(),
  };

  factory SetupDraft.fromJson(Map<String, dynamic> json) {
    final rawBranches = json['branches'] as List<dynamic>?;
    final rawStaff = json['staff'] as List<dynamic>?;
    final rawServices = json['services'] as List<dynamic>?;

    return SetupDraft(
      organization: OrganizationDraft.fromJson(json['organization'] as Map<String, dynamic>),
      branches: rawBranches == null
          ? [createEmptyBranch()]
          : rawBranches.map((branch) => BranchDraft.fromJson(branch as Map<String, dynamic>)).toList(),
      staff: rawStaff == null
          ? [createEmptyStaff()]
          : rawStaff.map((member) => StaffDraft.fromJson(member as Map<String, dynamic>)).toList(),
      services: rawServices == null
          ? [createEmptyService()]
          : rawServices.map((service) => ServiceDraft.fromJson(service as Map<String, dynamic>)).toList(),
    );
  }
}

int _draftEntityIdCounter = 0;

String _generateDraftEntityId() {
  _draftEntityIdCounter += 1;
  return '${DateTime.now().microsecondsSinceEpoch}_$_draftEntityIdCounter';
}

/// Whether [id] was generated locally for an unsaved setup entity.
///
/// Hydrated backend rows use UUIDs; wizard-created rows use
/// `<microsecondsSinceEpoch>_<counter>`.
bool isSetupDraftEntityId(String id) {
  final underscore = id.indexOf('_');
  if (underscore <= 0) {
    return false;
  }
  return RegExp(r'^\d+$').hasMatch(id.substring(0, underscore));
}

List<WorkingDay> createDefaultWorkingDays() {
  return DAYS_OF_WEEK
      .map(
        (day) =>
            WorkingDay(day: day.id, enabled: day.id != 'fri' && day.id != 'sat', openTime: '09:00', closeTime: '17:00'),
      )
      .toList();
}

BranchDraft createEmptyBranch() {
  return BranchDraft(
    id: _generateDraftEntityId(),
    name: '',
    code: '',
    mobile: '',
    mapLocation: '',
    workingDays: createDefaultWorkingDays(),
  );
}

StaffDraft createEmptyStaff() {
  return StaffDraft(
    id: _generateDraftEntityId(),
    name: '',
    mobile: '',
    username: '',
    password: '',
    role: '',
    branchIds: const [],
  );
}

ServiceDraft createEmptyService() {
  return ServiceDraft(id: _generateDraftEntityId(), name: '', price: null);
}

SetupDraft createDefaultSetup() {
  return SetupDraft(
    organization: const OrganizationDraft(name: '', timezone: 'Africa/Cairo', currency: 'EGP'),
    branches: [createEmptyBranch()],
    staff: [createEmptyStaff()],
    services: [createEmptyService()],
  );
}
