import 'package:flutter/material.dart';
import 'package:flutter_example/user/_state.dart';
import 'package:flutter_example/widgets/custom_form_field.dart';

class UserPage extends StatelessWidget {
  const UserPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.user;

    return Scaffold(
      appBar: AppBar(title: const Text('User')),
      body: Column(
        children: [
          Text(user.userId.toString()),
          CustomFormField(
            label: 'URL',
            icon: Icons.link,
            initialValue: user.url,
            onChanged: (value) {
              user.setUrl(value);
            },
          ),
          CustomFormField(
            label: 'Username',
            icon: Icons.person,
            initialValue: user.username,
            onChanged: (value) {
              user.setUsername(value);
            },
          ),
          CustomFormField(
            label: 'Surname',
            icon: Icons.person_outline,
            initialValue: user.surname,
            onChanged: (value) {
              user.setSurname(value);
            },
          ),
        ],
      ),
    );
  }
}
