import 'dart:io';

import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

void main() {
  final now = DateTime(2024);

  final vaultNode = VaultNode('vault');
  final fileNode = FileNode('file');
  final c1 = ChangeNode('c1');
  final c2 = ChangeNode('c2');
  final c3 = ChangeNode('c3');
  final moveNode = MoveNode('move1');
  final delNode = DeleteNode('del1');

  final graph = Graph<NodeRecord>(root: vaultNode);
  graph.addNode(fileNode);
  graph.addNode(c1);
  graph.addNode(c2);
  graph.addNode(c3);
  graph.addNode(moveNode);
  graph.addNode(delNode);

  graph.addEdge(vaultNode, fileNode);
  graph.addEdge(fileNode, c1);
  graph.addEdge(c1, c2);
  graph.addEdge(c2, c3);
  graph.addEdge(c3, moveNode);
  graph.addEdge(moveNode, delNode);

  graph.updateNodeData(
    'vault',
    VaultRecord(
      key: 'vault',
      vaultId: 'v1',
      isSynced: true,
      createdAt: now,
      name: 'My Vault',
    ),
  );
  graph.updateNodeData(
    'file',
    FileRecord(
      key: 'file',
      vaultId: 'v1',
      parentKey: 'vault',
      isSynced: true,
      createdAt: now.add(const Duration(seconds: 1)),
      fileId: 'f1',
      path: '/notes/hello.md',
    ),
  );
  graph.updateNodeData(
    'c1',
    ChangeRecord(
      key: 'c1',
      vaultId: 'v1',
      parentKey: 'file',
      isSynced: true,
      createdAt: now.add(const Duration(seconds: 2)),
      fileId: 'f1',
      blobId: 'blob-aabbccdd',
      sizeBytes: 1024,
    ),
  );
  graph.updateNodeData(
    'c2',
    ChangeRecord(
      key: 'c2',
      vaultId: 'v1',
      parentKey: 'c1',
      isSynced: true,
      createdAt: now.add(const Duration(seconds: 3)),
      fileId: 'f1',
      blobId: 'blob-eeff0011',
      sizeBytes: 2048,
    ),
  );
  graph.updateNodeData(
    'c3',
    ChangeRecord(
      key: 'c3',
      vaultId: 'v1',
      parentKey: 'c2',
      isSynced: false,
      createdAt: now.add(const Duration(seconds: 4)),
      fileId: 'f1',
      blobId: 'blob-22334455',
      sizeBytes: 3000,
    ),
  );
  graph.updateNodeData(
    'move1',
    MoveRecord(
      key: 'move1',
      vaultId: 'v1',
      parentKey: 'c3',
      isSynced: false,
      createdAt: now.add(const Duration(seconds: 5)),
      fileId: 'f1',
      fromPath: '/notes/hello.md',
      toPath: '/notes/world.md',
    ),
  );
  graph.updateNodeData(
    'del1',
    DeleteRecord(
      key: 'del1',
      vaultId: 'v1',
      parentKey: 'move1',
      isSynced: false,
      createdAt: now.add(const Duration(seconds: 6)),
      fileId: 'f1',
    ),
  );

  final html = GraphHtmlGenerator().generate(graph);
  const outPath = '/tmp/rhyolite_graph.html';
  File(outPath).writeAsStringSync(html);
  print('Generated: $outPath');
}
