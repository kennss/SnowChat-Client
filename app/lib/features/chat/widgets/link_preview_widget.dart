/// @file        link_preview_widget.dart
/// @description URL link-preview widget — card display based on OG metadata, image/title/description/domain, URL open
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-03-30)
///
/// @functions
///  - LinkPreviewWidget: URL link-preview card widget (StatefulWidget)

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/link_preview_service.dart';
import '../../../shared/constants/colors.dart';

class LinkPreviewWidget extends StatefulWidget {
  final String url;
  final LinkPreviewService previewService;

  const LinkPreviewWidget({
    super.key,
    required this.url,
    required this.previewService,
  });

  @override
  State<LinkPreviewWidget> createState() => _LinkPreviewWidgetState();
}

class _LinkPreviewWidgetState extends State<LinkPreviewWidget> {
  LinkPreviewData? _data;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _fetchPreview();
  }

  Future<void> _fetchPreview() async {
    final data = await widget.previewService.fetchPreview(widget.url);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
      _failed = data == null;
    });
  }

  Future<void> _openUrl() async {
    final uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: SizedBox(
          height: 2,
          child: LinearProgressIndicator(
            backgroundColor: SnowColors.surfaceLight,
            color: SnowColors.primaryDim,
          ),
        ),
      );
    }

    if (_failed || _data == null || !_data!.hasContent) {
      return const SizedBox.shrink();
    }

    final data = _data!;

    return GestureDetector(
      onTap: _openUrl,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          color: SnowColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SnowColors.divider, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            if (data.imageUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                ),
                child: Image.network(
                  data.imageUrl!,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 64,
                    height: 64,
                    child: Icon(
                      Icons.link_rounded,
                      color: SnowColors.textTertiary,
                      size: 24,
                    ),
                  ),
                ),
              ),

            // Text content
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (data.title != null)
                      Text(
                        data.title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SnowColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (data.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        data.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SnowColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      data.domain,
                      style: const TextStyle(
                        color: SnowColors.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
