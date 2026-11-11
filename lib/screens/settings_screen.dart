import 'package:flutter/material.dart';

import 'manage_list_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('목록관리 - 위치정보'),
          ),
          ListTile(
            leading: const Icon(Icons.stairs_outlined),
            title: const Text('층'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const ManageListScreen(listType: 'floor', title: '층'),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home_work_outlined),
            title: const Text('장소1'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ManageListScreen(
                  listType: 'place_large',
                  title: '장소1',
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('장소2'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ManageListScreen(
                  listType: 'place_medium',
                  title: '장소2',
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('장소3'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ManageListScreen(
                  listType: 'place_small',
                  title: '장소3',
                ),
              ),
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('목록관리 - 분류'),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('분류'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const ManageListScreen(listType: 'category', title: '분류'),
              ),
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('목록관리 - 품목'),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('품목'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const ManageListScreen(listType: 'item', title: '품목'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
