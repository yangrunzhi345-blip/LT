import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/operations/operation_result.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../models/adventure_config.dart';
import '../../../models/narrative_map.dart';
import '../../../models/worldview_details.dart';
import '../../../providers/riverpod_providers.dart';
import '../../../widgets/narr_aitor_loading.dart';

class MapConnectionData {
  final String fromNodeId;
  final String toNodeId;
  final String type;
  final bool isBidirectional;

  const MapConnectionData({
    required this.fromNodeId,
    required this.toNodeId,
    required this.type,
    required this.isBidirectional,
  });
}

class MapNodeData {
  final String id;
  final String name;
  final String icon;
  final String type;
  final MapTerrainType terrainType;
  final String description;
  final double x;
  final double y;
  final bool explored;
  final bool isCurrent;
  final int travelCost;

  const MapNodeData({
    required this.id,
    required this.name,
    this.icon = '\u{1F4CD}',
    this.type = 'wild',
    this.terrainType = MapTerrainType.plains,
    this.description = '',
    required this.x,
    required this.y,
    this.explored = false,
    this.isCurrent = false,
    this.travelCost = 5,
  });
}

class WorldMapData {
  final List<MapNodeData> nodes;
  final List<MapConnectionData> connections;

  const WorldMapData({
    required this.nodes,
    this.connections = const [],
  });
}

class WorldMapScreen extends ConsumerStatefulWidget {
  final AdventureConfig? config;
  final void Function(MapNodeData node)? onMoveTo;
  final int? adventureId;

  const WorldMapScreen({
    super.key,
    this.config,
    this.onMoveTo,
    this.adventureId,
  });

  @override
  ConsumerState<WorldMapScreen> createState() => _WorldMapScreenState();
}

class _WorldMapScreenState extends ConsumerState<WorldMapScreen> {
  late final Future<WorldMapData> _mapFuture = _loadMap();

  String _extractWorldviewDetail() {
    final snapshot = widget.config?.worldviewSnapshot;
    if (snapshot == null) return '';
    final detailJson = snapshot['detail_json'];
    if (detailJson is! Map<String, dynamic>) return '';
    try {
      final details = WorldviewDetails.fromJson(detailJson);
      final confirmed = details.confirmedModules();
      final buffer = StringBuffer();
      for (final key in [
        'locations',
        'overview',
        'world_rules',
        'world_state'
      ]) {
        final module = confirmed[key];
        if (module != null) {
          buffer.writeln('[$key]');
          buffer.writeln(module is Map
              ? (module['text'] ?? module).toString()
              : module.toString());
        }
      }
      return buffer.toString().trim();
    } catch (_) {
      return '';
    }
  }

  Future<WorldMapData> _loadMap() async {
    final adventureId = widget.adventureId;
    if (adventureId == null) return const WorldMapData(nodes: []);

    final controller = ref.read(adventureGameControllerProvider);
    final graph = await controller.ensureMapInitialized(
      adventureId: adventureId,
      seeds: const [],
    );

    if (graph.nodes.isNotEmpty) {
      return _graphToMapData(graph);
    }

    final worldviewSummary = widget.config?.worldview ?? '';
    final worldviewDetail = _extractWorldviewDetail();
    final openingScene = widget.config?.effectiveOpeningScene ?? '';

    final result = await controller.generateAiMap(
      adventureId: adventureId,
      worldviewSummary: worldviewSummary,
      worldviewDetail: worldviewDetail,
      openingScene: openingScene,
    );

    switch (result) {
      case OperationSuccess<NarrativeMapGraph>(value: final graph):
        return _graphToMapData(graph);
      case OperationFailure<NarrativeMapGraph>():
        return const WorldMapData(nodes: []);
    }
  }

  WorldMapData _graphToMapData(NarrativeMapGraph graph) {
    final visibleNodeIds = graph.nodes.map((n) => n.id).toSet();
    return WorldMapData(
      nodes: graph.nodes
          .map((node) => MapNodeData(
                id: node.id,
                name: node.displayName,
                icon: node.icon.isEmpty ? node.terrainType.icon : node.icon,
                type: node.nodeType.name,
                terrainType: node.terrainType,
                description: node.description,
                x: node.positionX,
                y: node.positionY,
                explored: node.discoveryState.index >=
                    MapDiscoveryState.visited.index,
                isCurrent: node.id == graph.currentNodeId,
              ))
          .toList(growable: false),
      connections: graph.connections
          .where((e) =>
              visibleNodeIds.contains(e.fromNodeId) &&
              visibleNodeIds.contains(e.toNodeId))
          .map((e) => MapConnectionData(
                fromNodeId: e.fromNodeId,
                toNodeId: e.toNodeId,
                type: e.type.name,
                isBidirectional: e.isBidirectional,
              ))
          .toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WorldMapData>(
      future: _mapFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('\u{1F5FA}\u{FE0F} 世界地图')),
            body: Center(
              child: snapshot.hasError
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: EmptyStateView(
                        icon: Icons.error_outline,
                        title: '地图加载失败',
                        message: '${snapshot.error}',
                      ),
                    )
                  : const NarrAItorLoading.normal(message: 'AI 正在生成地图...'),
            ),
          );
        }
        return _buildMap(context, snapshot.data!);
      },
    );
  }

  Widget _buildMap(BuildContext context, WorldMapData mapData) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCompact = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      appBar: AppBar(title: const Text('\u{1F5FA}\u{FE0F} 世界地图')),
      body: SafeArea(
        child: Padding(
          padding: isCompact
              ? const EdgeInsets.fromLTRB(8, 6, 8, 8)
              : const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(isCompact ? 12 : 20),
                    border: Border.all(
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.08),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(isCompact ? 12 : 20),
                    child: mapData.nodes.isEmpty
                        ? Center(
                            child: Text(
                              '暂无地图数据',
                              style: TextStyle(
                                  color: isDark ? Colors.white54 : Colors.grey),
                            ),
                          )
                        : WorldMapView(
                            nodes: mapData.nodes,
                            connections: mapData.connections,
                            isDark: isDark,
                            onMoveTo: (node) {
                              Navigator.of(context).pop();
                              widget.onMoveTo?.call(node);
                            },
                            onViewDetails: (node) =>
                                _showNodeDetails(context, node, isDark),
                          ),
                  ),
                ),
              ),
              SizedBox(height: isCompact ? 8 : 12),
              _buildLegend(isDark, isCompact),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegend(bool isDark, bool isCompact) {
    final surface = isDark ? AppColors.darkSurface : Colors.white;
    final items = [
      _LegendDot(
          isDark: isDark,
          label: '当前位置',
          color: AppColors.accent,
          hasRing: true),
      _LegendDot(isDark: isDark, label: '已探索', color: const Color(0xFF8FBC8F)),
      _LegendDot(
          isDark: isDark,
          label: '未探索',
          color: Colors.transparent,
          hollow: true),
    ];
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 10 : 14,
        vertical: isCompact ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(isCompact ? 12 : 16),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        ),
      ),
      child: isCompact
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                  children: items
                      .expand((i) => [i, const SizedBox(width: 14)])
                      .toList()),
            )
          : Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: items,
            ),
    );
  }

  void _showNodeDetails(BuildContext ctx, MapNodeData node, bool isDark) {
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.white54 : Colors.grey;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          (node.explored ? node.terrainType.color : Colors.grey)
                              .withValues(alpha: 0.16),
                    ),
                    child: Center(
                        child: Text(node.icon,
                            style: const TextStyle(fontSize: 22))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      node.name,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusChip(
                      node.terrainType.label, node.terrainType.color, isDark),
                  _statusChip(
                    node.explored ? '已探索' : '未探索',
                    node.explored ? AppColors.success : AppColors.warning,
                    isDark,
                  ),
                  if (node.isCurrent)
                    _statusChip('当前位置', AppColors.accent, isDark),
                ],
              ),
              if (node.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  node.description,
                  style: TextStyle(
                      fontSize: 13, height: 1.5, color: textSecondary),
                ),
              ],
              if (!node.isCurrent && widget.onMoveTo != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      widget.onMoveTo?.call(node);
                    },
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent),
                    icon: const Icon(Icons.explore_outlined, size: 18),
                    label: const Text('移动到这里'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class WorldMapView extends StatefulWidget {
  final List<MapNodeData> nodes;
  final bool isDark;
  final List<MapConnectionData> connections;
  final void Function(MapNodeData)? onMoveTo;
  final void Function(MapNodeData)? onViewDetails;

  const WorldMapView({
    super.key,
    required this.nodes,
    this.isDark = false,
    this.connections = const [],
    this.onMoveTo,
    this.onViewDetails,
  });

  @override
  State<WorldMapView> createState() => _WorldMapViewState();
}

class _WorldMapViewState extends State<WorldMapView> {
  late final TransformationController _transformationController;
  Size? _fittedViewport;
  Size? _lastViewport;
  double _scale = 1;

  static const double _canvasWidth = 2400;
  static const double _canvasHeight = 1800;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController()
      ..addListener(_handleTransformChanged);
  }

  @override
  void didUpdateWidget(covariant WorldMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.nodes, widget.nodes)) {
      _fittedViewport = null;
    }
  }

  void _handleTransformChanged() {
    final nextScale = _transformationController.value.getMaxScaleOnAxis();
    if ((nextScale - _scale).abs() < 0.05 || !mounted) return;
    setState(() => _scale = nextScale);
  }

  @override
  void dispose() {
    _transformationController
      ..removeListener(_handleTransformChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layoutNodes = widget.nodes
        .map((n) => n._withCanvasCoords(_canvasWidth, _canvasHeight))
        .toList(growable: false);

    return LayoutBuilder(builder: (context, constraints) {
      final viewport = Size(constraints.maxWidth, constraints.maxHeight);
      _lastViewport = viewport;
      final minimumScale = _coverScale(viewport);
      _scheduleInitialFit(viewport);
      return Stack(
        children: [
          InteractiveViewer(
            transformationController: _transformationController,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(400),
            minScale: minimumScale,
            maxScale: 8.0,
            child: Container(
              width: _canvasWidth,
              height: _canvasHeight,
              color: widget.isDark
                  ? const Color(0xFF141824)
                  : const Color(0xFFF1E7CE),
              child: CustomPaint(
                painter: _MapPainter(
                  nodes: layoutNodes,
                  connections: widget.connections,
                  isDark: widget.isDark,
                ),
                child: Stack(
                  children: layoutNodes.map(_buildNodeMarker).toList(),
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: _buildZoomControls(),
          ),
        ],
      );
    });
  }

  Widget _buildNodeMarker(MapNodeData node) {
    final showLabel = _shouldShowLabel(node);
    final unexploredFill =
        widget.isDark ? const Color(0xFF2A3040) : const Color(0xFFB9B2A2);
    final fillColor = node.explored ? node.terrainType.color : unexploredFill;
    final ringColor = node.isCurrent
        ? AppColors.accent
        : (node.explored
            ? (widget.isDark
                ? Colors.white.withValues(alpha: 0.55)
                : Colors.white)
            : Colors.grey.withValues(alpha: 0.7));
    return Positioned(
      left: node.x - 60,
      top: node.y - 32,
      child: GestureDetector(
        onTap: () => widget.onViewDetails?.call(node),
        onLongPress: () => widget.onMoveTo?.call(node),
        child: Tooltip(
          message:
              '${node.name} (${node.terrainType.label})\n${node.description}'
              '${!node.explored ? "\n(未探索)" : ""}',
          child: SizedBox(
            width: 120,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: fillColor,
                    border: Border.all(
                        color: ringColor, width: node.isCurrent ? 3.5 : 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: widget.isDark ? 0.45 : 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Opacity(
                      opacity: node.explored ? 1 : 0.65,
                      child:
                          Text(node.icon, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                ),
                if (showLabel) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color:
                          (widget.isDark ? AppColors.darkSurface : Colors.white)
                              .withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: (node.isCurrent
                                ? AppColors.accent
                                : (widget.isDark ? Colors.white : Colors.black))
                            .withValues(alpha: node.isCurrent ? 0.5 : 0.08),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: node.explored
                                ? node.terrainType.color
                                : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          node.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: node.isCurrent
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: node.isCurrent
                                ? AppColors.accent
                                : (widget.isDark
                                    ? Colors.white
                                    : Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildZoomControls() {
    final hairline =
        (widget.isDark ? Colors.white : Colors.black).withValues(alpha: 0.08);
    return Container(
      decoration: BoxDecoration(
        color: (widget.isDark ? AppColors.darkSurface : Colors.white)
            .withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(
            icon: Icons.add,
            isDark: widget.isDark,
            onPressed: () => _animateZoom(_scale * 1.5),
          ),
          Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: hairline),
          _ZoomButton(
            icon: Icons.remove,
            isDark: widget.isDark,
            onPressed: () => _animateZoom(_scale / 1.5),
          ),
          Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: hairline),
          _ZoomButton(
            icon: Icons.my_location,
            isDark: widget.isDark,
            onPressed: _focusCurrentLocation,
          ),
        ],
      ),
    );
  }

  void _animateZoom(double targetScale) {
    final clamped = targetScale.clamp(0.2, 8.0);
    final matrix = _transformationController.value.clone();
    final currentScale = matrix.getMaxScaleOnAxis();
    final factor = clamped / currentScale;
    const centerX = _canvasWidth / 2;
    const centerY = _canvasHeight / 2;
    matrix
      ..translateByDouble(centerX, centerY, 0, 1.0)
      ..scaleByDouble(factor, factor, 1, 1)
      ..translateByDouble(-centerX, -centerY, 0, 1.0);
    _transformationController.value = matrix;
  }

  void _focusCurrentLocation() {
    final viewport = _lastViewport;
    if (viewport == null || viewport.isEmpty) return;
    final currentNode = widget.nodes.where((n) => n.isCurrent).firstOrNull;
    final focus = currentNode == null
        ? const Offset(_canvasWidth / 2, _canvasHeight / 2)
        : Offset(currentNode.x * _canvasWidth, currentNode.y * _canvasHeight);
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final offsetX = (viewport.width / 2 - focus.dx * scale).clamp(
      viewport.width - _canvasWidth * scale,
      0.0,
    );
    final offsetY = (viewport.height / 2 - focus.dy * scale).clamp(
      viewport.height - _canvasHeight * scale,
      0.0,
    );
    _transformationController.value = Matrix4.identity()
      ..translateByDouble(offsetX, offsetY, 0, 1.0)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _scheduleInitialFit(Size viewport) {
    if (!viewport.width.isFinite ||
        !viewport.height.isFinite ||
        viewport.isEmpty ||
        _fittedViewport == viewport) {
      return;
    }
    _fittedViewport = viewport;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _fittedViewport != viewport) return;
      final initialScale = max(1.0, _coverScale(viewport));
      final currentNode = widget.nodes.where((n) => n.isCurrent).firstOrNull;
      final focus = currentNode == null
          ? const Offset(_canvasWidth / 2, _canvasHeight / 2)
          : Offset(currentNode.x * _canvasWidth, currentNode.y * _canvasHeight);
      final offsetX = (viewport.width / 2 - focus.dx * initialScale).clamp(
        viewport.width - _canvasWidth * initialScale,
        0.0,
      );
      final offsetY = (viewport.height / 2 - focus.dy * initialScale).clamp(
        viewport.height - _canvasHeight * initialScale,
        0.0,
      );
      _transformationController.value = Matrix4.identity()
        ..translateByDouble(offsetX, offsetY, 0, 1.0)
        ..scaleByDouble(initialScale, initialScale, 1, 1);
    });
  }

  double _coverScale(Size viewport) {
    return max(
      viewport.width / _canvasWidth,
      viewport.height / _canvasHeight,
    ).clamp(0.15, 8.0);
  }

  bool _shouldShowLabel(MapNodeData node) {
    if (node.isCurrent) return true;
    final bucket = node.id.hashCode.abs();
    if (_scale < 1.5) return false;
    if (_scale < 3.0) return bucket % 4 == 0;
    if (_scale < 5.0) return bucket % 2 == 0;
    return true;
  }
}

extension on MapNodeData {
  MapNodeData _withCanvasCoords(double canvasWidth, double canvasHeight) {
    return MapNodeData(
      id: id,
      name: name,
      icon: icon,
      type: type,
      terrainType: terrainType,
      description: description,
      x: x * canvasWidth,
      y: y * canvasHeight,
      explored: explored,
      isCurrent: isCurrent,
      travelCost: travelCost,
    );
  }
}

class _MapPainter extends CustomPainter {
  final List<MapNodeData> nodes;
  final List<MapConnectionData> connections;
  final bool isDark;

  _MapPainter({
    required this.nodes,
    required this.connections,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawConnections(canvas);
    _drawNodeDecorations(canvas);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..color = isDark ? const Color(0xFF141824) : const Color(0xFFF1E7CE),
    );

    // 径向暗角：让羊皮纸画布更有纵深
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          rect.center,
          size.longestSide * 0.75,
          [
            Colors.transparent,
            (isDark ? Colors.black : const Color(0xFF5C4B2A))
                .withValues(alpha: isDark ? 0.4 : 0.10),
          ],
        ),
    );

    // 淡经纬线网格，强化地图质感
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : const Color(0xFF8A744A))
          .withValues(alpha: isDark ? 0.04 : 0.07)
      ..strokeWidth = 1;
    for (var x = 300.0; x < size.width; x += 300) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 300.0; y < size.height; y += 300) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    _drawCompass(canvas, Offset(size.width - 140, 150));
  }

  void _drawCompass(Canvas canvas, Offset center) {
    final ink = (isDark ? Colors.white : const Color(0xFF6B5B3E))
        .withValues(alpha: isDark ? 0.28 : 0.4);
    canvas.drawCircle(
      center,
      46,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ink,
    );
    canvas.drawCircle(
      center,
      38,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ink.withValues(alpha: 0.6),
    );
    final north = Path()
      ..moveTo(center.dx, center.dy - 34)
      ..lineTo(center.dx - 8, center.dy)
      ..lineTo(center.dx + 8, center.dy)
      ..close();
    canvas.drawPath(north, Paint()..color = ink);
    final south = Path()
      ..moveTo(center.dx, center.dy + 34)
      ..lineTo(center.dx - 8, center.dy)
      ..lineTo(center.dx + 8, center.dy)
      ..close();
    canvas.drawPath(south, Paint()..color = ink.withValues(alpha: 0.35));
    final labelPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: 'N',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink),
      )
      ..layout();
    labelPainter.paint(
      canvas,
      Offset(center.dx - labelPainter.width / 2, center.dy - 62),
    );
  }

  void _drawConnections(Canvas canvas) {
    if (connections.isEmpty) return;
    final byId = {for (final node in nodes) node.id: node};

    for (final conn in connections) {
      final a = byId[conn.fromNodeId];
      final b = byId[conn.toNodeId];
      if (a == null || b == null) continue;

      final (coreColor, casingColor, width, dashed) =
          _connectionStyle(conn.type);

      final path = Path()
        ..moveTo(a.x, a.y)
        ..quadraticBezierTo(
          (a.x + b.x) / 2,
          (a.y + b.y) / 2 - 24,
          b.x,
          b.y,
        );
      final drawn = dashed ? _dashedPath(path, dash: 12, gap: 9) : path;

      if (casingColor != null) {
        canvas.drawPath(
          drawn,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = width + 3
            ..color = casingColor,
        );
      }
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width
          ..color = coreColor,
      );

      if (!conn.isBidirectional) {
        _drawDirectionArrow(canvas, path, coreColor);
      }
    }
  }

  (Color, Color?, double, bool) _connectionStyle(String type) {
    return switch (type) {
      'road' => (
          const Color(0xFFD8B36A),
          const Color(0xFF7A5C24).withValues(alpha: 0.85),
          4.0,
          false,
        ),
      'path' => (
          const Color(0xFFA08A63).withValues(alpha: 0.9),
          null,
          2.5,
          true
        ),
      'river' => (
          const Color(0xFF7FB2E5),
          const Color(0xFF2E5F9E).withValues(alpha: 0.9),
          4.0,
          false,
        ),
      'seaRoute' => (
          const Color(0xFF5E97D6).withValues(alpha: 0.9),
          null,
          3.0,
          true
        ),
      'portal' || 'teleport' => (
          const Color(0xFFA56FE0).withValues(alpha: 0.95),
          null,
          3.0,
          true,
        ),
      _ => (
          (isDark ? Colors.white : const Color(0xFF6B5B3E))
              .withValues(alpha: 0.55),
          null,
          2.5,
          false,
        ),
    };
  }

  void _drawDirectionArrow(Canvas canvas, Path path, Color color) {
    for (final metric in path.computeMetrics()) {
      final tangent = metric.getTangentForOffset(metric.length * 0.88);
      if (tangent == null) continue;
      final tip = tangent.position;
      final angle = tangent.angle;
      final arrow = Path()
        ..moveTo(tip.dx + cos(angle) * 12, tip.dy + sin(angle) * 12)
        ..lineTo(tip.dx + cos(angle + 2.6) * 11, tip.dy + sin(angle + 2.6) * 11)
        ..lineTo(tip.dx + cos(angle - 2.6) * 11, tip.dy + sin(angle - 2.6) * 11)
        ..close();
      canvas.drawPath(arrow, Paint()..color = color);
    }
  }

  void _drawNodeDecorations(Canvas canvas) {
    for (final node in nodes) {
      if (node.isCurrent) {
        // 当前位置：柔和光晕 + 强调环
        canvas.drawCircle(
          Offset(node.x, node.y),
          52,
          Paint()
            ..color = AppColors.accent.withValues(alpha: isDark ? 0.22 : 0.16),
        );
        canvas.drawCircle(
          Offset(node.x, node.y),
          52,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = AppColors.accent.withValues(alpha: 0.6),
        );
      } else if (!node.explored) {
        // 未探索：虚线圈示意迷雾区域
        final ring = Path()
          ..addOval(
              Rect.fromCircle(center: Offset(node.x, node.y), radius: 42));
        canvas.drawPath(
          _dashedPath(ring, dash: 6, gap: 6),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color =
                (isDark ? Colors.white : Colors.black).withValues(alpha: 0.35),
        );
      }
    }
  }

  Path _dashedPath(Path source, {required double dash, required double gap}) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      var drawn = 0.0;
      while (drawn < metric.length) {
        final end = min(drawn + dash, metric.length);
        result.addPath(metric.extractPath(drawn, end), Offset.zero);
        drawn += dash + gap;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) =>
      oldDelegate.nodes != nodes ||
      oldDelegate.connections != connections ||
      oldDelegate.isDark != isDark;
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onPressed;

  const _ZoomButton(
      {required this.icon, required this.isDark, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon,
            size: 18, color: isDark ? Colors.white70 : Colors.black54),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final String label;
  final Color color;
  final bool isDark;
  final bool hasRing;
  final bool hollow;

  const _LegendDot({
    required this.label,
    required this.color,
    required this.isDark,
    this.hasRing = false,
    this.hollow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hollow ? Colors.transparent : color,
          border: Border.all(
            color: hasRing
                ? AppColors.accent
                : (hollow ? (isDark ? Colors.white38 : Colors.grey) : color),
            width: hasRing ? 2 : 1.2,
          ),
        ),
      ),
      const SizedBox(width: 5),
      Text(label,
          style: TextStyle(
              fontSize: 10.5,
              color: isDark ? Colors.white54 : Colors.grey[600])),
    ]);
  }
}
