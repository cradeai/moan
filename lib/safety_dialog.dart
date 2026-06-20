import 'package:flutter/material.dart';

Future<void> showSafetyDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.grey.shade900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.shield_outlined, color: Colors.greenAccent),
          SizedBox(width: 10),
          Text('Drive Safely', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: const Text(
        'This app uses your phone\'s GPS to track driving in real time.\n\n'
        '• Mount your phone before driving — never hold it.\n'
        '• Best used with a passenger.\n'
        '• Keep your full attention on the road.\n'
        '• Stop and park before checking your score or sharing trips.',
        style: TextStyle(color: Colors.white70, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('I Understand', style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}
