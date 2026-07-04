import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/navigation/command_bar.dart';

/// Default mock command palette items — mirrors web `buildDefaultCommandItems`.
List<CommandItem> buildDefaultShellCommandItems(void Function(String navId) onNavigate) {
  CommandItem nav(String id, String label) => CommandItem(
    id: id,
    group: 'Navigate',
    label: label,
    onSelect: () => onNavigate(id),
  );

  return [
    nav('patients', 'Patients'),
    nav('appointments', 'Appointments'),
    nav('billing', 'Billing'),
    nav('reports', 'Reports'),
    CommandItem(
      id: 'patient-1',
      group: 'Patients',
      label: 'Layla Hassan',
      meta: 'MRN · 10482 · Last visit 2 days ago',
      avatarName: 'Layla Hassan',
      onSelect: () => onNavigate('patients'),
    ),
    CommandItem(
      id: 'patient-2',
      group: 'Patients',
      label: 'Omar Farouk',
      meta: 'MRN · 11029 · Appointment today',
      avatarName: 'Omar Farouk',
      onSelect: () => onNavigate('patients'),
    ),
    CommandItem(
      id: 'patient-3',
      group: 'Patients',
      label: 'Nadia El-Sayed',
      meta: 'MRN · 9876 · Follow-up due',
      avatarName: 'Nadia El-Sayed',
      onSelect: () => onNavigate('patients'),
    ),
    CommandItem(
      id: 'new-patient',
      group: 'Actions',
      label: 'New patient',
      icon: const Icon(Icons.person_add_outlined, size: 16),
      shortcut: const ['⌘', 'N'],
      onSelect: () {},
    ),
    CommandItem(
      id: 'new-invoice',
      group: 'Actions',
      label: 'New invoice',
      icon: const Icon(Icons.description_outlined, size: 16),
      shortcut: const ['⌘', 'I'],
      onSelect: () {},
    ),
    CommandItem(
      id: 'new-appointment',
      group: 'Actions',
      label: 'New appointment',
      icon: const Icon(Icons.add, size: 16),
      onSelect: () {},
    ),
  ];
}
