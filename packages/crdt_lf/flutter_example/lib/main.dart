   import 'package:flutter/material.dart';
   import 'package:crdt_lf/crdt_lf.dart';

   void main() {
     runApp(const MyApp());
   }

   class MyApp extends StatelessWidget {
     const MyApp({super.key});

     @override
     Widget build(BuildContext context) {
       return MaterialApp(
         title: 'CRDT Test',
         theme: ThemeData(primarySwatch: Colors.blue),
         home: const MyHomePage(),
       );
     }
   }

   class MyHomePage extends StatefulWidget {
     const MyHomePage({super.key});

     @override
     State<MyHomePage> createState() => _MyHomePageState();
   }

   class _MyHomePageState extends State<MyHomePage> {
     final CRDTDocument _document = CRDTDocument();
     late CRDTTextHandler _textHandler;

     @override
     void initState() {
       super.initState();
       _textHandler = CRDTTextHandler(_document, 'test-text');
       _textHandler.insert(0, 'Hello');
     }

     @override
     Widget build(BuildContext context) {
       return Scaffold(
         appBar: AppBar(title: const Text('CRDT Test')),
         body: Center(
           child: Column(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
               Text('Current text: ${_textHandler.value}'),
               const SizedBox(height: 20),
               ElevatedButton(
                 onPressed: () {
                   setState(() {
                     _textHandler.insert(_textHandler.length, ' World!');
                   });
                 },
                 child: const Text('Add Text'),
               ),
             ],
           ),
         ),
       );
     }
   }