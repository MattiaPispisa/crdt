import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/widgets.dart';

/// Throws a [FlutterError] when the handler type parameter [H] was left unset
/// (i.e. resolved to the base `Handler`).
void assertHandlerGenericIsSet<H extends Handler<dynamic>>(String widget) {
  if (H == Handler<dynamic>) {
    throw FlutterError(
      '$widget was used without a handler type parameter.\n'
      'Specify the handler type, e.g. $widget<CRDTListHandler<int>>(...).',
    );
  }
}

/// What a widget bound to a deleted handler shows: [deletedBuilder], or an
/// empty box when it is `null`.
Widget buildDeleted(BuildContext context, WidgetBuilder? deletedBuilder) =>
    deletedBuilder?.call(context) ?? const SizedBox.shrink();
