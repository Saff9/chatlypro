import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:hive/hive.dart';

class SecureKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onClose;

  const SecureKeyboard({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onClose,
  });

  @override
  State<SecureKeyboard> createState() => _SecureKeyboardState();
}

class _SecureKeyboardState extends State<SecureKeyboard> {
  bool _isShiftEnabled = false;
  bool _isSymbolMode = false;
  bool _isEmojiMode = false;
  int _activeEmojiCategory = 0;
  String _selectedEmojiSize = 'medium'; // small, medium, large, xlarge
  Color _themeColor = const Color(0xFF8083FF); // Keyboard branding tint

  final List<String> _categories = ['😃', '🐶', '🍎', '💡', '🚩'];

  final List<List<String>> _categorizedEmojis = [
    // 0: Smileys
    ['😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '😊', '😇', '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😗', '😙', '😚', '😋', '😛', '😝', '😜', '🤪', '🤨', '🧐', '🤓', '😎', '🥸', '🤩', '🥳', '😏', '😒', '😞', '😔'],
    // 1: Animals
    ['🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵', '🐔', '🐧', '🐦', '🦆', '🦅', '🦉', '🦇', '🐺', '🐗', '🐴', '🦄', '🐝', '🪱', '🐛', '🦋', '🐌', '🐞', '🐜', '🪰', '🪲', '🪳'],
    // 2: Food
    ['🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐', '🍈', '🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🍆', '🥑', '🥦', '🥬', '🥒', '🌶️', '🫑', '🌽', '🥕', '🫒', '🧄', '🧅', '🥔', '🍠', '🥐', '🥯', '🍞', '🥖'],
    // 3: Objects
    ['💡', '🕯️', '🔌', '🔋', '💻', '🖥️', '🖨️', '⌨️', '🖱️', '💽', '💾', '💿', '📀', '📱', '☎️', '📟', '📠', '📺', '📻', '🎙️', '🎚️', '🎛️', '🧭', '⏱️', '💵', '🪙', '💳', '💎', '🔑', '🔒', '🔓', '🛡️', '🔨', '🪓', '⛏️', '🔧'],
    // 4: Flags
    ['🏳️', '🏴', '🏁', '🚩', '🏳️‍🌈', '🏳️‍⚧️', '🇺🇸', '🇬🇧', '🇨🇦', '🇩🇪', '🇯🇵', '🇮🇳', '🇨🇳', '🇫🇷', '🇧🇷', '🇮🇹', '🇷🇺', '🇪🇸', '🇲🇽', '🇰🇷', '🇦🇺', '🇿🇦', '🇪🇺', '🇸🇬', '🇵🇰', '🇸🇦', '🇹🇷', '🇪🇬', '🇳🇬', '🇮🇩', '🇲🇾', '🇺🇦', '🇵🇱', '🇳🇱', '🇸🇪', '🇨🇭']
  ];

  void _handleKeyPress(String char) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    
    int start = selection.isValid ? selection.start : text.length;
    int end = selection.isValid ? selection.end : text.length;

    String textToInsert = char;
    // Apply size formatting for single emojis
    if (_isEmojiMode && _selectedEmojiSize != 'medium') {
      textToInsert = '[size:$_selectedEmojiSize]$char';
    }

    final newText = text.replaceRange(start, end, textToInsert);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + textToInsert.length),
    );
  }

  void _handleBackspace() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;

    if (text.isEmpty) return;

    int start = selection.isValid ? selection.start : text.length;
    int end = selection.isValid ? selection.end : text.length;

    if (start == end) {
      if (start == 0) return;

      // Check if we are deleting an emoji with a [size:xxx] tag
      if (start >= 12 && text.substring(0, start).contains(RegExp(r'\[size:\w+\][^]$'))) {
        final lastTagIndex = text.substring(0, start).lastIndexOf('[size:');
        if (lastTagIndex != -1) {
          final newText = text.replaceRange(lastTagIndex, start, '');
          widget.controller.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: lastTagIndex),
          );
          return;
        }
      }

      final newText = text.replaceRange(start - 1, start, '');
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start - 1),
      );
    } else {
      final newText = text.replaceRange(start, end, '');
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: const Color(0xFF13131B).withValues(alpha: 0.92),
        border: const Border(
          top: BorderSide(color: Colors.white10, width: 1.0),
        ),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Condensed Size & Key Theme Selector Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.01),
                    border: Border(
                      bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04), width: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Emoji Size Selectors
                      if (_isEmojiMode)
                        Row(
                          children: [
                            const Text('SIZE: ', style: TextStyle(fontSize: 9, color: Colors.white38, fontWeight: FontWeight.bold)),
                            _buildSizeChip('S', 'small'),
                            _buildSizeChip('M', 'medium'),
                            _buildSizeChip('L', 'large'),
                            _buildSizeChip('XL', 'xlarge'),
                          ],
                        )
                      else
                        // Key Tint Options
                        Row(
                          children: [
                            const Text('THEME: ', style: TextStyle(fontSize: 9, color: Colors.white38, fontWeight: FontWeight.bold)),
                            _buildThemeDot(const Color(0xFF8083FF)),
                            _buildThemeDot(const Color(0xFF10B981)),
                            _buildThemeDot(const Color(0xFFFFB300)),
                          ],
                        ),
                      
                      // Use System Keyboard Choice button
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () async {
                          final box = await Hive.openBox('settings');
                          await box.put('use_secure_keyboard_default', false);
                          widget.onClose();
                        },
                        icon: const Icon(Icons.keyboard_outlined, size: 12, color: Colors.white60),
                        label: const Text('USE SYSTEM KEYBOARD', style: TextStyle(fontSize: 8, color: Colors.white60, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),

                // Top controls bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    border: Border(
                      bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.security_rounded, size: 13, color: Color(0xFF10B981)),
                          const SizedBox(width: 6),
                          Text(
                            'SECURE KEYBOARD ACTIVE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF10B981).withValues(alpha: 0.8),
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_hide_rounded, size: 18, color: Colors.white60),
                        onPressed: widget.onClose,
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),

                // Emoji Categories Header (Only shown in Emoji Mode)
                if (_isEmojiMode)
                  Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.02),
                      border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.03), width: 0.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(_categories.length, (idx) {
                        final isActive = _activeEmojiCategory == idx;
                        return GestureDetector(
                          onTap: () => setState(() => _activeEmojiCategory = idx),
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: isActive ? _themeColor : Colors.transparent,
                                  width: 2.0,
                                ),
                              ),
                            ),
                            child: Opacity(
                              opacity: isActive ? 1.0 : 0.4,
                              child: Text(
                                _categories[idx],
                                style: const TextStyle(
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),

                // Custom keyboard keys area
                Container(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isEmojiMode)
                        _buildEmojiLayout()
                      else
                        _buildKeypadLayout(),
                      const SizedBox(height: 5),
                      _buildBottomKeysRow(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSizeChip(String label, String value) {
    final isSelected = _selectedEmojiSize == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedEmojiSize = value),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? _themeColor.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? _themeColor : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: isSelected ? _themeColor : Colors.white38,
          ),
        ),
      ),
    );
  }

  Widget _buildThemeDot(Color color) {
    final isSelected = _themeColor == color;
    return GestureDetector(
      onTap: () => setState(() => _themeColor = color),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: isSelected ? Colors.white : Colors.transparent, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildKeypadLayout() {
    final List<List<String>> qwertyRows = [
      ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
      ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
      ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
    ];

    final List<List<String>> symbolRows = [
      ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
      ['-', '/', ':', ';', '(', ')', '\$', '&', '@', '"'],
      ['.', ',', '?', '!', '\'', '_', '+'],
    ];

    final rows = _isSymbolMode ? symbolRows : qwertyRows;

    return Column(
      children: [
        _buildRow(rows[0]),
        const SizedBox(height: 5),
        _buildRow(rows[1]),
        const SizedBox(height: 5),
        Row(
          children: [
            if (!_isSymbolMode)
              _buildSpecialKey(
                child: Icon(
                  Icons.arrow_upward_rounded,
                  color: _isShiftEnabled ? _themeColor : Colors.white60,
                  size: 16,
                ),
                onTap: () => setState(() => _isShiftEnabled = !_isShiftEnabled),
                flex: 12,
              )
            else
              _buildSpecialKey(
                child: const Text('=', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                onTap: () => _handleKeyPress('='),
                flex: 12,
              ),
            const SizedBox(width: 4),
            Expanded(
              flex: 76,
              child: _buildRow(rows[2]),
            ),
            const SizedBox(width: 4),
            _buildSpecialKey(
              child: const Icon(Icons.backspace_outlined, color: Colors.white70, size: 16),
              onTap: _handleBackspace,
              flex: 12,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRow(List<String> keys) {
    return Row(
      children: keys.map((key) {
        final displayChar = _isShiftEnabled ? key.toUpperCase() : key;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: _buildKey(displayChar, onTap: () => _handleKeyPress(displayChar)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKey(String char, {required VoidCallback onTap, bool isSpace = false}) {
    return _KeyAnimationWrapper(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: isSpace ? 0.08 : 0.05),
          border: Border.all(color: Colors.white.withValues(alpha: 0.04), width: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          char,
          style: TextStyle(
            fontSize: isSpace ? 11 : 15,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }

  Widget _buildSpecialKey({required Widget child, required VoidCallback onTap, required int flex, Color? backgroundColor}) {
    return Expanded(
      flex: flex,
      child: _KeyAnimationWrapper(
        onTap: onTap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildEmojiLayout() {
    final emojis = _categorizedEmojis[_activeEmojiCategory];
    return SizedBox(
      height: 145,
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: emojis.length,
        itemBuilder: (context, index) {
          final emoji = emojis[index];
          return GestureDetector(
            onTap: () => _handleKeyPress(emoji),
            behavior: HitTestBehavior.opaque,
            child: Container(
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomKeysRow() {
    return Row(
      children: [
        _buildSpecialKey(
          child: Text(
            _isSymbolMode ? 'ABC' : '?123',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          onTap: () => setState(() {
            _isSymbolMode = !_isSymbolMode;
            _isEmojiMode = false;
          }),
          flex: 15,
        ),
        const SizedBox(width: 4),
        _buildSpecialKey(
          child: Icon(
            _isEmojiMode ? Icons.keyboard_hide_rounded : Icons.sentiment_satisfied_alt_rounded,
            color: Colors.white70,
            size: 18,
          ),
          onTap: () => setState(() {
            _isEmojiMode = !_isEmojiMode;
          }),
          flex: 15,
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: 50,
          child: _buildKey(
            'SPACE',
            onTap: () => _handleKeyPress(' '),
            isSpace: true,
          ),
        ),
        const SizedBox(width: 4),
        _buildSpecialKey(
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 14),
          onTap: widget.onSend,
          backgroundColor: _themeColor.withValues(alpha: 0.85),
          flex: 20,
        ),
      ],
    );
  }
}

class _KeyAnimationWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _KeyAnimationWrapper({required this.child, required this.onTap});

  @override
  State<_KeyAnimationWrapper> createState() => _KeyAnimationWrapperState();
}

class _KeyAnimationWrapperState extends State<_KeyAnimationWrapper> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 60),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.90).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        _controller.forward();
      },
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () {
        _controller.reverse();
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}
