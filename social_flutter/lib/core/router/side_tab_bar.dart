// core/router/side_tab_bar.dart — the tabs' bar on a wide window: the bottom
// bar turned on its side (the shell in app_router.dart decides which shows).
// Each tab takes an equal share of the bar's height, as each takes an equal
// share of the bottom bar's width, and a window too short for that scrolls
// them. NavigationRail cannot share out its height — its tabs sit in a column
// only as tall as they are — so the bar is drawn here, styled by
// navigationRailTheme and labelled for screen readers the way the rail is.

import 'package:flutter/material.dart';
import 'package:ntripi/core/ui/app_theme.dart';

/// One of the shell's tabs, as both bars draw it.
typedef ShellTab = ({Widget icon, Widget activeIcon, String label});

class SideTabBar extends StatelessWidget {
  const SideTabBar({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
  });

  final List<ShellTab> tabs;
  final int currentIndex;

  /// Called on every tap, the open tab's included — the shell resets that one.
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        // Foreground: the hairline on the edge facing the content stays over
        // the bar's own surface.
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: BorderDirectional(end: BorderSide(color: context.nt.border)),
        ),
        child: Material(
          // A Material of its own, so a tab's ink is drawn on the bar.
          color: NavigationRailTheme.of(context).backgroundColor,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, bar) => SingleChildScrollView(
                child: ConstrainedBox(
                  // At least the bar's height, shared out evenly; a shorter
                  // window gets the tabs' own height and scrolls.
                  constraints: BoxConstraints(minHeight: bar.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < tabs.length; i++)
                          Expanded(
                            child: _SideTab(
                              tab: tabs[i],
                              index: i,
                              count: tabs.length,
                              selected: i == currentIndex,
                              onTap: () => onTap(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _SideTab extends StatelessWidget {
  const _SideTab({
    required this.tab,
    required this.index,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final ShellTab tab;
  final int index;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = NavigationRailTheme.of(context);
    return Semantics(
      container: true,
      selected: selected,
      child: Stack(
        children: [
          InkResponse(
            onTap: onTap,
            // The whole share is the tab, as each item is on the bottom bar.
            containedInkWell: true,
            highlightShape: BoxShape.rectangle,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconTheme.merge(
                      data: (selected
                              ? theme.selectedIconTheme
                              : theme.unselectedIconTheme) ??
                          const IconThemeData(),
                      child: selected ? tab.activeIcon : tab.icon,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tab.label,
                      // A long label wraps under its icon; the bar keeps its width.
                      textAlign: TextAlign.center,
                      style: selected
                          ? theme.selectedLabelTextStyle
                          : theme.unselectedLabelTextStyle,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // "Tab 2 of 5", as NavigationRail and the bottom bar announce it.
          Semantics(
            label: MaterialLocalizations.of(context)
                .tabLabel(tabIndex: index + 1, tabCount: count),
          ),
        ],
      ),
    );
  }
}
