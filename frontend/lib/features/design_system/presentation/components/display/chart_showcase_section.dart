import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_chart.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _ChartCopy {
  const _ChartCopy({
    required this.sectionDescription,
    required this.lineLabel,
    required this.barLabel,
    required this.stackedBarLabel,
    required this.donutLabel,
    required this.appointments,
    required this.newLabel,
    required this.followUp,
    required this.services,
    required this.weeklyAppointments,
    required this.weeklyAppointmentsBar,
    required this.appointmentTypes,
    required this.revenueByService,
  });

  final String sectionDescription;
  final String lineLabel;
  final String barLabel;
  final String stackedBarLabel;
  final String donutLabel;
  final String appointments;
  final String newLabel;
  final String followUp;
  final String services;
  final String weeklyAppointments;
  final String weeklyAppointmentsBar;
  final String appointmentTypes;
  final String revenueByService;
}

const _copyEn = _ChartCopy(
  sectionDescription:
      'Hand-rolled SVG-equivalent charts via CustomPainter. Line, bar, stacked bar, and donut.',
  lineLabel: 'Line',
  barLabel: 'Bar',
  stackedBarLabel: 'Stacked bar',
  donutLabel: 'Donut',
  appointments: 'Appointments',
  newLabel: 'New',
  followUp: 'Follow-up',
  services: 'Services',
  weeklyAppointments: 'Weekly appointments',
  weeklyAppointmentsBar: 'Weekly appointments bar',
  appointmentTypes: 'Appointment types',
  revenueByService: 'Revenue by service',
);

const _copyAr = _ChartCopy(
  sectionDescription:
      'رسوم بيانية مرسومة يدويًا عبر CustomPainter. خطي، أعمدة، أعمدة مكدسة، ودائري.',
  lineLabel: 'خطي',
  barLabel: 'أعمدة',
  stackedBarLabel: 'أعمدة مكدسة',
  donutLabel: 'دائري',
  appointments: 'المواعيد',
  newLabel: 'جديد',
  followUp: 'متابعة',
  services: 'الخدمات',
  weeklyAppointments: 'المواعيد الأسبوعية',
  weeklyAppointmentsBar: 'المواعيد الأسبوعية - أعمدة',
  appointmentTypes: 'أنواع المواعيد',
  revenueByService: 'الإيرادات حسب الخدمة',
);

_ChartCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

const _labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
const _appointmentData = [12, 18, 15, 22, 19];
const _newData = [5, 8, 6, 10, 7];
const _followUpData = [7, 10, 9, 12, 12];
const _servicesData = [40, 30, 20, 10];

/// Chart showcase (web `ChartShowcase`).
class ChartShowcaseSection extends ConsumerWidget {
  const ChartShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'chart',
      title: 'Chart primitives',
      description: copy.sectionDescription,
      componentName: 'AppChart',
      child: ShowcaseDemoGrid(
        columns: 2,
        children: [
          ShowcaseDemo(
            label: copy.lineLabel,
            propsHint: 'type="line"',
            child: AppChart(
              type: AppChartType.line,
              series: [ChartSeries(label: copy.appointments, data: _appointmentData)],
              labels: _labels,
              ariaLabel: copy.weeklyAppointments,
            ),
          ),
          ShowcaseDemo(
            label: copy.barLabel,
            propsHint: 'type="bar"',
            child: AppChart(
              type: AppChartType.bar,
              series: [ChartSeries(label: copy.appointments, data: _appointmentData)],
              ariaLabel: copy.weeklyAppointmentsBar,
            ),
          ),
          ShowcaseDemo(
            label: copy.stackedBarLabel,
            propsHint: 'type="stacked-bar"',
            child: AppChart(
              type: AppChartType.stackedBar,
              series: [
                ChartSeries(label: copy.newLabel, data: _newData),
                ChartSeries(label: copy.followUp, data: _followUpData),
              ],
              ariaLabel: copy.appointmentTypes,
            ),
          ),
          ShowcaseDemo(
            label: copy.donutLabel,
            propsHint: 'type="donut"',
            child: AppChart(
              type: AppChartType.donut,
              series: [ChartSeries(label: copy.services, data: _servicesData)],
              ariaLabel: copy.revenueByService,
            ),
          ),
        ],
      ),
    );
  }
}
