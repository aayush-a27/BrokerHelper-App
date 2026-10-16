import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/app_scaffold.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// The broker's own details — shown on shared property cards — and a
/// summary of the diary.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final BrokerProfile _initial =
      context.read<AppState>().profile ?? BrokerProfile(name: '');
  late final _name = TextEditingController(text: _initial.name);
  late final _phone = TextEditingController(text: _initial.phone);
  late final _email = TextEditingController(text: _initial.email);
  late final _agency = TextEditingController(text: _initial.agency);
  late final _rera = TextEditingController(text: _initial.reraNumber);

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _agency, _rera]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    context.read<AppState>().saveProfile(BrokerProfile(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          agency: _agency.text.trim(),
          reraNumber: _rera.text.trim(),
        ));
    FocusScope.of(context).unfocus();
    showToast(context, 'Profile saved', icon: Icons.check_circle_outline);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final openLeads = state.openLeads.length;
    final openDeals = state.openDeals.length;

    return MainScaffold(
      title: 'My profile',
      embedded: widget.embedded,
      showQuickAdd: false,
      showSearch: false,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Center(
              child: CircleAvatar(
                radius: 40,
                child: Text(
                  (state.profile ?? _initial).initials,
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          Form(
            key: _form,
            child: DetailCard(
              title: 'My details',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Name *'),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? 'Name is required' : null,
                      ),
                      Gap.m,
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone'),
                      ),
                      Gap.m,
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                      ),
                      Gap.m,
                      TextFormField(
                        controller: _agency,
                        textCapitalization: TextCapitalization.words,
                        decoration:
                            const InputDecoration(labelText: 'Agency or firm'),
                      ),
                      Gap.m,
                      TextFormField(
                        controller: _rera,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                            labelText: 'RERA agent registration no.'),
                      ),
                      Gap.m,
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          DetailCard(
            title: 'My diary',
            children: [
              InfoRow(
                label: 'Leads',
                value: '${state.leads.length} ($openLeads open)',
                icon: Icons.filter_alt_outlined,
              ),
              InfoRow(
                label: 'Contacts',
                value: '${state.contacts.length}',
                icon: Icons.contacts_outlined,
              ),
              InfoRow(
                label: 'Listings',
                value: '${state.properties.length}',
                icon: Icons.home_work_outlined,
              ),
              InfoRow(
                label: 'Deals',
                value: '${state.deals.length} ($openDeals open)',
                icon: Icons.handshake_outlined,
              ),
              InfoRow(
                label: 'Commission',
                value: '${formatMoney(state.totalReceivedCommission)} received · '
                    '${formatMoney(state.totalPendingCommission)} pending',
                icon: Icons.payments_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
