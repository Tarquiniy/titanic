// lib/screens/home_profile_card.dart
import 'package:flutter/material.dart';
import 'package:titanic/models/app_user.dart';
import 'package:titanic/theme/app_theme.dart';
import 'package:titanic/widgets/art_deco_button.dart';

class HomeProfileCard extends StatelessWidget {
  final AppUser user;
  final VoidCallback onTransfer;
  final VoidCallback onOpenInventory;

  const HomeProfileCard({
    Key? key,
    required this.user,
    required this.onTransfer,
    required this.onOpenInventory,
  }) : super(key: key);

  Widget _buildBalanceItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.2),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: TitanicTheme.softIvory.withOpacity(0.8),
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color,
            fontFamily: 'PlayfairDisplay',
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            TitanicTheme.darkEmerald.withOpacity(0.9),
            TitanicTheme.deepTeal.withOpacity(0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: TitanicTheme.gold.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: TitanicTheme.goldGradient,
                  border: Border.all(
                    color: TitanicTheme.gold,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.account_circle,
                  size: 40,
                  color: TitanicTheme.softIvory,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${user.firstName} ${user.lastName}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: TitanicTheme.softIvory,
                        fontFamily: 'PlayfairDisplay',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${user.username}',
                      style: TextStyle(
                        fontSize: 14,
                        color: TitanicTheme.gold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: TitanicTheme.tealShade.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: TitanicTheme.tealShade,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        user.role.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: TitanicTheme.softIvory,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Инвентарь',
                icon: Icon(Icons.inventory_2, color: TitanicTheme.gold),
                onPressed: onOpenInventory,
              )
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBalanceItem(
                icon: Icons.monetization_on,
                label: 'ВОЙСЫ (V)',
                value: user.vBalance.toStringAsFixed(0),
                color: TitanicTheme.tealShade,
              ),
              Container(
                width: 1,
                height: 50,
                color: TitanicTheme.gold.withOpacity(0.3),
              ),
              _buildBalanceItem(
                icon: Icons.memory,
                label: 'МАЙНДЫ (M)',
                value: user.mBalance.toStringAsFixed(0),
                color: TitanicTheme.richCopper,
              ),
            ],
          ),
          const SizedBox(height: 20),
          ArtDecoButton(
            text: 'ПЕРЕВОД ВОЙСОВ',
            onPressed: onTransfer,
            icon: Icons.swap_horiz,
            width: double.infinity,
            height: 50,
          ),
        ],
      ),
    );
  }
}
