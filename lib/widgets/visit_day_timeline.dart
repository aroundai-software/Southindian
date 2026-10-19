import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/activity_log_model.dart';
import 'package:Orderx/widgets/location_address_widget.dart';

class VisitDayTimeline extends StatelessWidget {
  final ActivityDayGroup day;
  final bool showAttendance;
  final bool showOrders;
  final bool showCollections;
  final Future<void> Function(ActivityLog log)? onOpenOrder;
  final Future<void> Function(ActivityLog log)? onOpenCollection;

  const VisitDayTimeline({
    super.key,
    required this.day,
    this.showAttendance = true,
    this.showOrders = true,
    this.showCollections = true,
    this.onOpenOrder,
    this.onOpenCollection,
  });

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat('EEE, dd MMM yyyy').format(day.day);
    final timeFmt = DateFormat('hh:mm a');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateText,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryBlue,
            ),
          ),
          const SizedBox(height: 8),
          if (showAttendance) ...[
            _infoRow(
              Icons.login,
              AppTheme.success,
              'Login',
              day.firstLogin == null
                  ? '—'
                  : timeFmt.format(day.firstLogin!) +
                      (day.logins.length > 1
                          ? '  (${day.logins.length} times)'
                          : ''),
              subtitle: day.logins.isNotEmpty &&
                      day.logins.first.latitude != null
                  ? LocationAddressWidget(
                      latitude: day.logins.first.latitude!,
                      longitude: day.logins.first.longitude!,
                    )
                  : null,
              trailing: day.logins.isNotEmpty &&
                      day.logins.first.latitude != null
                  ? _mapButton(
                      context,
                      day.logins.first.latitude!,
                      day.logins.first.longitude!,
                    )
                  : null,
            ),
            const SizedBox(height: 6),
            _infoRow(
              Icons.logout,
              AppTheme.error,
              'Logout',
              day.stillLoggedIn
                  ? 'Still logged in'
                  : day.lastLogout == null
                      ? '—'
                      : timeFmt.format(day.lastLogout!) +
                          (day.logouts.length > 1
                              ? '  (${day.logouts.length} times)'
                              : ''),
              subtitle: !day.stillLoggedIn &&
                      day.logouts.isNotEmpty &&
                      day.logouts.last.latitude != null
                  ? LocationAddressWidget(
                      latitude: day.logouts.last.latitude!,
                      longitude: day.logouts.last.longitude!,
                    )
                  : null,
              trailing: !day.stillLoggedIn &&
                      day.logouts.isNotEmpty &&
                      day.logouts.last.latitude != null
                  ? _mapButton(
                      context,
                      day.logouts.last.latitude!,
                      day.logouts.last.longitude!,
                    )
                  : null,
            ),
          ],
          if (showOrders || showCollections) ...[
            if (day.punches.isNotEmpty && showOrders) ...[
              const SizedBox(height: 10),
              const Text(
                'Location Punches',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              ...day.punches.reversed.map((punch) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 18, color: AppTheme.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              punch.notes != null && punch.notes!.isNotEmpty
                                  ? '${punch.notes} • ${timeFmt.format(punch.timestamp)}'
                                  : 'Punched at ${timeFmt.format(punch.timestamp)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: punch.notes != null &&
                                        punch.notes!.isNotEmpty
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: AppTheme.darkGrey,
                              ),
                            ),
                            if (punch.latitude != null &&
                                punch.longitude != null)
                              LocationAddressWidget(
                                latitude: punch.latitude!,
                                longitude: punch.longitude!,
                              ),
                          ],
                        ),
                      ),
                      if (punch.latitude != null && punch.longitude != null)
                        _mapButton(
                          context,
                          punch.latitude!,
                          punch.longitude!,
                        ),
                    ],
                  ),
                );
              }),
            ],
            if (showCollections) ...[
              const SizedBox(height: 10),
              const Text(
                'Collections',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              if (day.collections.isEmpty)
                const Text(
                  'No collections',
                  style: TextStyle(color: AppTheme.grey, fontSize: 13),
                )
              else
                ...day.collections.reversed.map((collection) {
                  final txn = collection.transactionId?.trim();
                  return InkWell(
                    onTap: onOpenCollection == null
                        ? null
                        : () => onOpenCollection!(collection),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.payments_outlined,
                            size: 18,
                            color: AppTheme.success,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  collection.customerName?.trim().isNotEmpty ==
                                          true
                                      ? collection.customerName!
                                      : 'Unknown customer',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.darkGrey,
                                  ),
                                ),
                                Text(
                                  collection.paymentMethod?.trim().isNotEmpty ==
                                          true
                                      ? collection.paymentMethod!
                                      : 'Payment',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.darkGrey,
                                  ),
                                ),
                                Text(
                                  (txn == null || txn.isEmpty)
                                      ? 'Txn: —'
                                      : 'Txn: $txn',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            timeFmt.format(collection.timestamp),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.grey,
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: AppTheme.grey,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
            if (showOrders) ...[
              const SizedBox(height: 10),
              const Text(
                'Orders created',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              if (day.orders.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'No orders',
                    style: TextStyle(color: AppTheme.grey, fontSize: 13),
                  ),
                )
              else
                ...day.orders.reversed.map((order) {
                  return InkWell(
                    onTap: onOpenOrder == null
                        ? null
                        : () => onOpenOrder!(order),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.receipt_long_outlined,
                              size: 18, color: AppTheme.primaryBlue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  order.orderNumber ?? 'Order',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryBlue,
                                  ),
                                ),
                                Text(
                                  order.customerName ?? 'Walk-in Customer',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.darkGrey,
                                  ),
                                ),
                                if (order.latitude != null &&
                                    order.longitude != null)
                                  LocationAddressWidget(
                                    latitude: order.latitude!,
                                    longitude: order.longitude!,
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            timeFmt.format(order.timestamp),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.grey,
                            ),
                          ),
                          if (order.latitude != null &&
                              order.longitude != null)
                            _mapButton(
                              context,
                              order.latitude!,
                              order.longitude!,
                            ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ],
        ],
      ),
    );
  }

  Widget _mapButton(BuildContext context, double lat, double lng) {
    return IconButton(
      icon: const Icon(Icons.map, size: 20, color: AppTheme.success),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      constraints: const BoxConstraints(),
      tooltip: 'View Location',
      onPressed: () async {
        final url = Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
        if (await canLaunchUrl(url)) {
          await launchUrl(url);
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open map')),
          );
        }
      },
    );
  }

  Widget _infoRow(
    IconData icon,
    Color color,
    String label,
    String value, {
    Widget? trailing,
    Widget? subtitle,
  }) {
    return Row(
      crossAxisAlignment: subtitle != null
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Padding(
          padding: EdgeInsets.only(top: subtitle != null ? 2.0 : 0),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(color: AppTheme.grey, fontSize: 13),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              if (subtitle != null) subtitle,
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }
}
