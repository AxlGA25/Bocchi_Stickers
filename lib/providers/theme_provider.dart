import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/theme.dart';

final themeMemberProvider =
    NotifierProvider<ThemeMemberNotifier, KessokuMember>(
  ThemeMemberNotifier.new,
);

class ThemeMemberNotifier extends Notifier<KessokuMember> {
  static const String _prefsFileName = 'kessoku_theme.json';

  @override
  KessokuMember build() {
    _loadSavedMember();
    return KessokuMember.bocchi;
  }

  Future<void> _loadSavedMember() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_prefsFileName');
      if (await file.exists()) {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final memberId = data['memberId'] as String?;
        state = KessokuMember.fromId(memberId);
      }
    } catch (_) {}
  }

  Future<void> selectMember(KessokuMember member) async {
    state = member;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_prefsFileName');
      await file.writeAsString(
        jsonEncode({'memberId': member.id}),
        flush: true,
      );
    } catch (_) {}
  }
}
