import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class BraceletStatusCard extends StatelessWidget {
  final bool isConnected;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const BraceletStatusCard({
    super.key,
    required this.isConnected,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isConnected
            ? AppColors.primaryContainer.withAlpha(80)
            : AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Animated dot
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isConnected ? const Color(0xFF4CAF50) : AppColors.outline,
              shape: BoxShape.circle,
              boxShadow: isConnected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF4CAF50).withAlpha(100),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected ? 'Bracelet Connected' : 'Bracelet Disconnected',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  isConnected
                      ? 'Streaming HR, Temp & Accelerometer'
                      : 'Tap to connect and start monitoring',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: isConnected ? onDisconnect : onConnect,
            style: OutlinedButton.styleFrom(
              foregroundColor: isConnected
                  ? AppColors.error
                  : AppColors.primary,
              side: BorderSide(
                color: isConnected
                    ? AppColors.error.withAlpha(150)
                    : AppColors.primary,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              textStyle: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(isConnected ? 'Disconnect' : 'Connect'),
          ),
        ],
      ),
    );
  }
}
