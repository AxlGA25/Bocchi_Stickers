import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/theme_provider.dart';
import 'home_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _scaleAnim = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _enterApp() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: const HomeScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeMember = ref.watch(themeMemberProvider);

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              activeMember.surfaceTint,
              Color.lerp(
                activeMember.surfaceTint,
                activeMember.primaryColor,
                0.28,
              )!,
              const Color(0xFF0B0C10),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              children: [
                const Spacer(),

                // Logo principal animado (o personaje elegido)
                ScaleTransition(
                  scale: _scaleAnim,
                  child: Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color:
                              activeMember.primaryColor.withValues(alpha: 0.45),
                          blurRadius: 36,
                          spreadRadius: 6,
                        ),
                      ],
                      border: Border.all(
                        color: Colors.white,
                        width: 4,
                      ),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        activeMember.assetPath,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Image.asset(
                          'assets/icon.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: activeMember.primaryColor,
                            alignment: Alignment.center,
                            child: Text(
                              activeMember.badgeEmoji,
                              style: const TextStyle(fontSize: 72),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Título con estilo Kessoku Band
                Text(
                  'BOCCHI STICKERS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: activeMember.primaryColor,
                        blurRadius: 16,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: activeMember.primaryColor.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: activeMember.primaryColor,
                      width: 1.2,
                    ),
                  ),
                  child: Text(
                    '⚡ Kessoku Band Edition • ${activeMember.fullName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  activeMember.quote,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontStyle: FontStyle.italic,
                    fontSize: 14,
                  ),
                ),

                const Spacer(),

                // Selector rápido de tema / integrante desde la portada
                const Text(
                  'ELIGE TU TEMA DE LAS QUESO KUBAN:',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: KessokuMember.values.map((member) {
                    final isSelected = member == activeMember;
                    return GestureDetector(
                      onTap: () => ref
                          .read(themeMemberProvider.notifier)
                          .selectMember(member),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? member.primaryColor
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? Colors.white
                                : member.primaryColor.withValues(alpha: 0.5),
                            width: isSelected ? 2.2 : 1.0,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              member.badgeEmoji,
                              style: const TextStyle(fontSize: 18),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              member.displayName,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color:
                                    isSelected && member == KessokuMember.nijika
                                        ? Colors.black87
                                        : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),

                // Botón principal para entrar al Home Screen
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: activeMember.primaryColor,
                      foregroundColor: activeMember == KessokuMember.nijika
                          ? Colors.black87
                          : Colors.white,
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: _enterApp,
                    icon: const Icon(Icons.music_note_rounded),
                    label: const Text('¡Entrar al Estudio de Stickers!'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
