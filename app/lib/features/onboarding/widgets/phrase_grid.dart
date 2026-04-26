/// @file        phrase_grid.dart
/// @description Mnemonic-phrase grid widget — display 24-word recovery phrase in a 3-column grid, with highlight and obscure support.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - PhraseGrid: StatelessWidget that renders the mnemonic word grid

import 'package:flutter/material.dart';
import '../../../shared/constants/colors.dart';

/// Displays a 24-word mnemonic phrase in a 3-column grid.
class PhraseGrid extends StatelessWidget {
  final List<String> words;
  final Set<int>? highlightIndices;
  final bool obscured;

  const PhraseGrid({
    super.key,
    required this.words,
    this.highlightIndices,
    this.obscured = false,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(words.length, (index) {
        final isHighlighted = highlightIndices?.contains(index) ?? false;
        return _WordChip(
          index: index + 1,
          word: obscured ? '******' : words[index],
          isHighlighted: isHighlighted,
        );
      }),
    );
  }
}

class _WordChip extends StatelessWidget {
  final int index;
  final String word;
  final bool isHighlighted;

  const _WordChip({
    required this.index,
    required this.word,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.of(context).size.width - 64) / 3;

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isHighlighted ? SnowColors.primaryBg : SnowColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: isHighlighted
            ? Border.all(color: SnowColors.primary, width: 1.5)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$index.',
            style: TextStyle(
              color: isHighlighted
                  ? SnowColors.primary
                  : SnowColors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              word,
              style: TextStyle(
                color: isHighlighted
                    ? SnowColors.primary
                    : SnowColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
