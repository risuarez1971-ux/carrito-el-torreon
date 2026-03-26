import 'package:flutter_test/flutter_test.dart';
import 'package:carrito_el_torreon/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ListaPreciosApp()),
    );
    // Verifica que la AppBar con el título carga correctamente
    expect(find.text('carrito El Torreón'), findsOneWidget);
  });
}