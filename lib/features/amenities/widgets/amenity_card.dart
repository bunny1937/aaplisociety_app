import 'package:flutter/material.dart';
import '../../member/pulse/pulse.dart';
import '../data/amenities_api.dart';
import 'amenity_bits.dart';

class AmenityCard extends StatelessWidget {
  final AmenitySummary amenity;
  final VoidCallback onTap;
  const AmenityCard({super.key, required this.amenity, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final hours = (amenity.openingTime != null && amenity.closingTime != null)
        ? '${amenity.openingTime} – ${amenity.closingTime}'
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(PulseTokens.radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PulseTokens.radius),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PulseTokens.radius),
              border: Border.all(color: t.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(amenity.name,
                              style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: t.fg1)),
                          const SizedBox(height: 3),
                          Text(
                            [
                              amenity.categoryName,
                              if (amenity.location != null &&
                                  amenity.location!.isNotEmpty)
                                amenity.location!,
                              if (hours != null) hours,
                            ].join(' · '),
                            style: TextStyle(fontSize: 12, color: t.fg4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    AmenityStatusPill(status: amenity.effective),
                  ],
                ),
                if (!amenity.capacity.unlimited) ...[
                  const SizedBox(height: 12),
                  CapacityBar(capacity: amenity.capacity),
                ],
                if (amenity.hasOpenSession) ...[
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      Icon(Icons.how_to_reg_outlined,
                          size: 15, color: t.success),
                      const SizedBox(width: 6),
                      Text("You are checked in here",
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: t.success)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
