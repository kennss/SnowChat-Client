/// @file        link_preview_service.dart
/// @description URL link preview service - OG metadata parsing, LRU cache, timeout handling.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - LinkPreviewData: link preview data class (title, description, imageUrl, domain)
///  - LinkPreviewService: service class that fetches OG metadata from a URL
///  - fetchPreview(url): parse OG metadata from URL and return LinkPreviewData
///  - extractUrls(text): extract URL list from text

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Data class for link preview metadata.
class LinkPreviewData {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String domain;

  const LinkPreviewData({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    required this.domain,
  });

  /// Whether this preview has any meaningful content to display.
  bool get hasContent => title != null || description != null;
}

/// Service that fetches and caches OG metadata for URLs.
///
/// - Fetches HTML and parses og:title, og:description, og:image tags
/// - Uses regex-based parsing (no heavy package dependency)
/// - In-memory LRU cache (max 100 entries)
/// - 5-second timeout per request
class LinkPreviewService {
  static const int _maxCacheSize = 100;
  static const Duration _timeout = Duration(seconds: 5);

  /// URL detection regex: matches http(s):// URLs.
  static final RegExp urlRegex = RegExp(
    r'https?://[^\s<>\[\]{}|\\^`"]+',
    caseSensitive: false,
  );

  /// LRU cache: URL -> LinkPreviewData (null = fetch failed / no data).
  final _cache = LinkedHashMap<String, LinkPreviewData?>();

  /// Set of URLs currently being fetched (to avoid duplicate requests).
  final _pending = <String>{};

  /// Extract all URLs from [text].
  static List<String> extractUrls(String text) {
    return urlRegex.allMatches(text).map((m) => m.group(0)!).toList();
  }

  /// Fetch OG metadata for [url].
  ///
  /// Returns cached data if available. Returns `null` if fetch fails
  /// or the page has no OG metadata.
  Future<LinkPreviewData?> fetchPreview(String url) async {
    // Check cache first
    if (_cache.containsKey(url)) {
      final cached = _cache.remove(url);
      // Move to end (most recently used)
      _cache[url] = cached;
      return cached;
    }

    // Avoid duplicate concurrent fetches
    if (_pending.contains(url)) return null;
    _pending.add(url);

    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) {
        _putCache(url, null);
        return null;
      }

      final html = response.body;
      final data = _parseOgTags(html, url, uri.host);
      _putCache(url, data);
      return data;
    } catch (e) {
      debugPrint('[LinkPreviewService] Failed to fetch $url: $e');
      _putCache(url, null);
      return null;
    } finally {
      _pending.remove(url);
    }
  }

  /// Parse OG tags from HTML using regex.
  LinkPreviewData? _parseOgTags(String html, String url, String host) {
    final title = _extractMetaContent(html, 'og:title') ??
        _extractHtmlTitle(html);
    final description = _extractMetaContent(html, 'og:description');
    final imageUrl = _extractMetaContent(html, 'og:image');

    if (title == null && description == null) return null;

    return LinkPreviewData(
      url: url,
      title: title,
      description: description,
      imageUrl: imageUrl,
      domain: host.replaceFirst('www.', ''),
    );
  }

  /// Extract content attribute from <meta property="[property]" content="...">
  static String? _extractMetaContent(String html, String property) {
    // Match both property="og:..." and name="og:..." patterns
    final patterns = [
      RegExp(
        '<meta[^>]+property=["\']$property["\'][^>]+content=["\']([^"\']*)["\']',
        caseSensitive: false,
      ),
      RegExp(
        '<meta[^>]+content=["\']([^"\']*)["\'][^>]+property=["\']$property["\']',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) {
        final content = match.group(1);
        if (content != null && content.isNotEmpty) return content;
      }
    }
    return null;
  }

  /// Fallback: extract <title> tag.
  static String? _extractHtmlTitle(String html) {
    final match =
        RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false)
            .firstMatch(html);
    return match?.group(1)?.trim();
  }

  /// Add to cache with LRU eviction.
  void _putCache(String url, LinkPreviewData? data) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[url] = data;
  }
}
