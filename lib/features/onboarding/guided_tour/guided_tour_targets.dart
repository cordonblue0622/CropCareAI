import 'package:flutter/material.dart';

/// Stable targets shared by the app shell and the guided tour overlay.
class AppTourKeys {
  AppTourKeys._();

  static final dashboardWelcome = GlobalKey(debugLabel: 'tourWelcome');
  static final dashboardOverview = GlobalKey(debugLabel: 'tourOverview');
  static final scanNavigation = GlobalKey(debugLabel: 'tourScan');
  static final cropDoctor = GlobalKey(debugLabel: 'tourCropDoctor');
  static final myCropsAppBar = GlobalKey(debugLabel: 'tourMyCrops');
  static final dailyTasks = GlobalKey(debugLabel: 'tourDailyTasks');
  static final notifications = GlobalKey(debugLabel: 'tourNotifications');
  static final accountHeader = GlobalKey(debugLabel: 'tourAccount');
}

class GuidedTourStep {
  final String title;
  final String description;
  final IconData icon;
  final GlobalKey? targetKey;
  final int tabIndex;
  final bool scrollToTop;
  final bool searchScrollable;

  const GuidedTourStep({
    required this.title,
    required this.description,
    required this.icon,
    required this.tabIndex,
    this.targetKey,
    this.scrollToTop = false,
    this.searchScrollable = false,
  });
}

class GuidedTourSteps {
  GuidedTourSteps._();

  static final values = <GuidedTourStep>[
    GuidedTourStep(
      title: 'Welcome to CropCare AI',
      description:
          'Your personal Vegetable Doctor. Identify possible crop diseases, learn about symptoms and treatment, and keep your crop records in one place.',
      icon: Icons.eco_outlined,
      targetKey: AppTourKeys.dashboardWelcome,
      tabIndex: 0,
      scrollToTop: true,
    ),
    GuidedTourStep(
      title: 'Your dashboard at a glance',
      description:
          'Farm Vitality shows your crops’ overall health. As you add crops and record progress, this area helps you review their condition.',
      icon: Icons.insights_rounded,
      targetKey: AppTourKeys.dashboardOverview,
      tabIndex: 0,
      scrollToTop: true,
    ),
    GuidedTourStep(
      title: 'Scan a crop',
      description:
          'Tap Scan to take a photo, upload an image, or record a short video. Before diagnosis, select the crop type so CropCare AI can assess your crop.',
      icon: Icons.document_scanner_outlined,
      targetKey: AppTourKeys.scanNavigation,
      tabIndex: 0,
    ),
    GuidedTourStep(
      title: 'Ask Crop Doctor',
      description:
          'Ask follow-up questions by text or voice and attach crop photos. Online AI consultation needs a connection; offline scans and saved guidance remain available with limited help.',
      icon: Icons.health_and_safety_outlined,
      targetKey: AppTourKeys.cropDoctor,
      tabIndex: 0,
    ),
    GuidedTourStep(
      title: 'Manage My Crops',
      description:
          'Use + to add a crop, or select a crop to review its diagnoses, treatment recommendations, health progress, and monitoring tasks.',
      icon: Icons.energy_savings_leaf_rounded,
      targetKey: AppTourKeys.myCropsAppBar,
      tabIndex: 1,
    ),
    GuidedTourStep(
      title: 'Follow daily tasks',
      description:
          'Review recommended activities and reminders here. Update tasks in the crop record as you complete them to keep track of your crop’s progress.',
      icon: Icons.task_alt_rounded,
      targetKey: AppTourKeys.dailyTasks,
      tabIndex: 0,
      searchScrollable: true,
    ),
    GuidedTourStep(
      title: 'Check notifications',
      description:
          'Open notifications for task reminders and important CropCare AI updates. Unread items are marked with a red badge.',
      icon: Icons.notifications_outlined,
      targetKey: AppTourKeys.notifications,
      tabIndex: 0,
      scrollToTop: true,
    ),
    GuidedTourStep(
      title: 'Profile and settings',
      description:
          'Manage your profile, app preferences, crop records, and support options here. You can replay this guide anytime from Support.',
      icon: Icons.person_outline_rounded,
      targetKey: AppTourKeys.accountHeader,
      tabIndex: 4,
    ),
    const GuidedTourStep(
      title: 'You’re all set!',
      description:
          'Start by scanning a crop, adding it to My Crops, or exploring Crop Doctor. Happy farming!',
      icon: Icons.celebration_outlined,
      tabIndex: 0,
      scrollToTop: true,
    ),
  ];
}
