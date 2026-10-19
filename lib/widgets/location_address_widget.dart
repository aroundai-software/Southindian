import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/utils/location_utils.dart';
import 'package:flutter/material.dart';

class LocationAddressWidget extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String? storedAddress;
  final bool compact;
  final bool showIcon;

  const LocationAddressWidget({
    super.key,
    required this.latitude,
    required this.longitude,
    this.storedAddress,
    this.compact = true,
    this.showIcon = true,
  });

  @override
  State<LocationAddressWidget> createState() => _LocationAddressWidgetState();
}

class _LocationAddressWidgetState extends State<LocationAddressWidget> {
  String? _address;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolveAddress();
  }

  @override
  void didUpdateWidget(covariant LocationAddressWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude ||
        oldWidget.storedAddress != widget.storedAddress) {
      _resolveAddress();
    }
  }

  Future<void> _resolveAddress() async {
    final stored = widget.storedAddress?.trim();
    if (stored != null &&
        stored.isNotEmpty &&
        !looksLikeCoordinates(stored)) {
      if (mounted) {
        setState(() {
          _address = stored;
          _loading = false;
        });
      }
      return;
    }

    final cached = cachedGeocodedAddress(widget.latitude, widget.longitude);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _address = cached;
          _loading = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _loading = true);
    final address = await reverseGeocodeAddress(
      widget.latitude,
      widget.longitude,
    );
    if (!mounted) return;
    setState(() {
      _address = address;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = _loading
        ? 'Finding address...'
        : (_address ?? 'Address unavailable');
    final style = TextStyle(
      fontSize: widget.compact ? 11 : 14,
      fontWeight: widget.compact ? FontWeight.normal : FontWeight.w600,
      color: widget.compact ? AppTheme.grey : AppTheme.darkGrey,
    );

    final label = Text(
      text,
      style: style,
      maxLines: widget.compact ? 2 : 4,
      overflow: TextOverflow.ellipsis,
    );

    if (!widget.showIcon) return label;

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.location_on,
            size: widget.compact ? 10 : 20,
            color: widget.compact ? AppTheme.grey : AppTheme.error,
          ),
          SizedBox(width: widget.compact ? 2 : 8),
          Expanded(child: label),
        ],
      ),
    );
  }
}
