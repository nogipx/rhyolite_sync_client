import 'dart:convert';

import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

class GraphHtmlGenerator {
  String generate(IGraph<NodeRecord> graph) {
    final visNodes = <Map<String, dynamic>>[];
    final visEdges = <Map<String, dynamic>>[];

    for (final entry in graph.nodes.entries) {
      final key = entry.key;
      final record = graph.getNodeData(key);
      if (record == null) continue;

      visNodes.add(_buildVisNode(record));
    }

    int edgeId = 0;
    for (final entry in graph.edges.entries) {
      final parent = entry.key;
      for (final child in entry.value) {
        visEdges.add({
          'id': edgeId++,
          'from': parent.key,
          'to': child.key,
          'arrows': 'to',
        });
      }
    }

    final nodesJson = jsonEncode(visNodes);
    final edgesJson = jsonEncode(visEdges);

    return _buildHtml(nodesJson, edgesJson);
  }

  Map<String, dynamic> _buildVisNode(NodeRecord record) {
    final (color, label, typeLabel) = switch (record) {
      VaultRecord r => ('#4a6fa5', r.name, 'VAULT'),
      FileRecord r => ('#4caf50', _short(r.path, 30), 'FILE'),
      ChangeRecord r => ('#ff9800', '${_short(r.blobId, 10)} (${r.sizeBytes}b)', 'CHANGE'),
      MoveRecord r => ('#9c27b0', '${_short(r.fromPath, 15)} → ${_short(r.toPath, 15)}', 'MOVE'),
      DeleteRecord r => ('#f44336', _short(r.fileId, 20), 'DEL'),
    };

    final tooltip = const JsonEncoder.withIndent('  ').convert(record.toLocalJson());

    return {
      'id': record.key,
      'label': '$typeLabel\n$label',
      'title': '<pre style="max-width:400px;white-space:pre-wrap">$tooltip</pre>',
      'color': {
        'background': color,
        'border': record.isSynced ? color : '#ffffff',
        'highlight': {'background': color, 'border': '#ffffff'},
      },
      'font': {'color': '#ffffff', 'size': 12},
      'shapeProperties': {
        'borderDashes': record.isSynced ? false : [6, 3],
      },
      'borderWidth': 2,
      'shape': 'box',
    };
  }

  String _short(String s, int maxLen) =>
      s.length <= maxLen ? s : '...${s.substring(s.length - maxLen)}';

  String _buildHtml(String nodesJson, String edgesJson) => '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Rhyolite Graph Visualizer</title>
  <script src="https://unpkg.com/vis-network/standalone/umd/vis-network.min.js"></script>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    html, body { height: 100%; overflow: hidden; background: #1e1e1e; color: #d4d4d4; font-family: monospace; }
    #header { position: fixed; top: 0; left: 0; right: 0; height: 40px; padding: 0 16px; background: #252526; border-bottom: 1px solid #333; display: flex; align-items: center; gap: 16px; z-index: 10; }
    #header h1 { font-size: 14px; color: #cccccc; }
    #network { position: fixed; top: 40px; left: 0; right: 0; bottom: 0; }
    #legend { display: flex; gap: 12px; flex-wrap: wrap; }
    .legend-item { display: flex; align-items: center; gap: 6px; font-size: 12px; }
    .legend-dot { width: 12px; height: 12px; border-radius: 2px; }
  </style>
</head>
<body>
  <div id="header">
    <h1>rhyolite_graph</h1>
    <div id="legend">
      <div class="legend-item"><div class="legend-dot" style="background:#4a6fa5"></div>vault</div>
      <div class="legend-item"><div class="legend-dot" style="background:#4caf50"></div>file</div>
      <div class="legend-item"><div class="legend-dot" style="background:#ff9800"></div>change</div>
      <div class="legend-item"><div class="legend-dot" style="background:#9c27b0"></div>move</div>
      <div class="legend-item"><div class="legend-dot" style="background:#f44336"></div>delete</div>
      <div class="legend-item"><div class="legend-dot" style="background:#555;border:2px dashed #fff"></div>unsynced</div>
    </div>
  </div>
  <div id="network"></div>
  <script>
    const nodes = new vis.DataSet($nodesJson);
    const edges = new vis.DataSet($edgesJson);
    const container = document.getElementById('network');
    const options = {
      layout: {
        hierarchical: {
          direction: 'UD',
          sortMethod: 'directed',
          nodeSpacing: 150,
          levelSeparation: 100,
        }
      },
      physics: { enabled: false },
      interaction: { tooltipDelay: 100, hover: true },
      edges: {
        color: { color: '#666', highlight: '#aaa' },
        smooth: { type: 'cubicBezier', forceDirection: 'vertical' },
      },
    };
    new vis.Network(container, { nodes, edges }, options);
  </script>
</body>
</html>
''';
}
