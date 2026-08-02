// A chat bubble that aligns left for assistant, right for user, with
// distinct background colors.
import 'package:flutter/material.dart';

import '../../../data/models/models.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.role, required this.child});

  final MessageRole role;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isUser = role == MessageRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isUser ? Colors.indigo.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: child,
      ),
    );
  }
}
