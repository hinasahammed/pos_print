import 'package:flutter/material.dart';
import 'package:pos_print/printer_screen.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Home"),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: ListTile(
                onTap: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PrinterScreen(),
                      ));
                },
                title: Text("Printer"),
                trailing: Icon(Icons.keyboard_arrow_right),
              ),
            )
          ],
        ),
      ),
    );
  }
}
