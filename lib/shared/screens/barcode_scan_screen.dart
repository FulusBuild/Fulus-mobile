import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/providers.dart';
import '../../core/errors/failure.dart';
import '../../core/theme/design_tokens.dart';
import '../widgets/widgets.dart';

/// Shared barcode scanner used by Sell and product creation/editing.
/// Camera permission, scan confirmation, and manual fallback remain owned
/// by the existing scanner service; this screen only presents the experience.
class BarcodeScanScreen extends ConsumerStatefulWidget {
  const BarcodeScanScreen({super.key, this.title = 'Scan a barcode'});
  final String title;
  static Future<String?> scan(BuildContext context, {String title = 'Scan a barcode'}) => Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => BarcodeScanScreen(title: title)));
  @override ConsumerState<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

enum _PermissionState { checking, granted, denied }
class _BarcodeScanScreenState extends ConsumerState<BarcodeScanScreen> {
  _PermissionState _permission = _PermissionState.checking;
  MobileScannerController? _controller;
  bool _handled = false;
  @override void initState(){super.initState();_checkPermission();}
  @override void dispose(){_controller?.dispose();super.dispose();}
  Future<void> _checkPermission() async {
    final service=ref.read(barcodeScannerServiceProvider);
    if(!await service.hasPermission){if(!mounted)return;final proceed=await showFulusPermissionPrimer(context,icon:FulusIcons.camera,message:"We'll ask to use your camera next — this lets you scan barcodes instead of typing them.");if(!proceed){if(mounted)setState(()=>_permission=_PermissionState.denied);return;}}
    try{await service.ensurePermission();if(!mounted)return;setState((){_controller=service.createController();_permission=_PermissionState.granted;});}on DeviceFailure{if(mounted)setState(()=>_permission=_PermissionState.denied);}
  }
  void _onDetect(BarcodeCapture capture){if(_handled)return;final service=ref.read(barcodeScannerServiceProvider);final result=service.extractResult(capture);if(result==null)return;_handled=true;service.confirmScan();Navigator.of(context).pop(result.rawValue);}
  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:Colors.black,body:SafeArea(child:switch(_permission){_PermissionState.checking=>const _ScannerLoading(),_PermissionState.denied=>_PermissionDeniedBody(onEnterManually:_enterManually),_PermissionState.granted=>_ScannerView(controller:_controller,title:widget.title,onDetect:_onDetect,onBack:()=>Navigator.of(context).pop(),onEnterManually:_enterManually)}));
  Future<void> _enterManually() async {final controller=TextEditingController();final value=await showDialog<String>(context:context,builder:(dialogContext)=>AlertDialog(title:const Text('Enter barcode'),scrollable:true,content:FulusTextField(label:'Barcode',controller:controller,keyboardType:TextInputType.text),actions:[TextButton(onPressed:()=>Navigator.of(dialogContext).pop(),child:const Text('Cancel')),FulusButton(label:'Use this',onPressed:(){final text=controller.text.trim();Navigator.of(dialogContext).pop(text.isEmpty?null:text);})]));controller.dispose();if(value!=null&&mounted)Navigator.of(context).pop(value);}
}
class _ScannerLoading extends StatelessWidget{const _ScannerLoading();@override Widget build(BuildContext context)=>const Center(child:Column(mainAxisSize:MainAxisSize.min,children:[SizedBox(width:28,height:28,child:CircularProgressIndicator(strokeWidth:2.5)),SizedBox(height:AppSpacing.md),Text('Preparing scanner…',style:TextStyle(color:Colors.white70))]));}
class _ScannerView extends StatelessWidget{const _ScannerView({required this.controller,required this.title,required this.onDetect,required this.onBack,required this.onEnterManually});final MobileScannerController? controller;final String title;final void Function(BarcodeCapture) onDetect;final VoidCallback onBack;final VoidCallback onEnterManually;@override Widget build(BuildContext context)=>Stack(fit:StackFit.expand,children:[MobileScanner(controller:controller,onDetect:onDetect),const _ScannerScrim(),const Center(child:_Viewfinder()),Positioned(top:AppSpacing.md,left:AppSpacing.md,right:AppSpacing.md,child:Row(children:[_ScannerCircleButton(icon:FulusIcons.arrowBack,tooltip:'Back',onPressed:onBack),const SizedBox(width:AppSpacing.sm),Expanded(child:Text(title,style:AppTypography.subheading.copyWith(color:Colors.white,fontWeight:FontWeight.w700))),_ScannerCircleButton(icon:FulusIcons.keyboard,tooltip:'Enter manually',onPressed:onEnterManually)])),Positioned(left:AppSpacing.xl,right:AppSpacing.xl,bottom:AppSpacing.xl,child:IgnorePointer(child:Column(children:[Text('Place the barcode inside the frame',textAlign:TextAlign.center,style:AppTypography.body.copyWith(color:Colors.white,fontWeight:FontWeight.w600)),const SizedBox(height:AppSpacing.xs),Text('Scanning happens automatically',textAlign:TextAlign.center,style:AppTypography.caption.copyWith(color:Colors.white70))]))) ]);}
class _ScannerScrim extends StatelessWidget{const _ScannerScrim();@override Widget build(BuildContext context)=>IgnorePointer(child:Container(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.black.withValues(alpha:.48),Colors.transparent,Colors.black.withValues(alpha:.62)],stops:const[0,.48,1]))));}
class _Viewfinder extends StatelessWidget{const _Viewfinder();@override Widget build(BuildContext context){final size=MediaQuery.sizeOf(context).width<420?248.0:286.0;return IgnorePointer(child:SizedBox(width:size,height:size,child:DecoratedBox(decoration:BoxDecoration(border:Border.all(color:Colors.white.withValues(alpha:.16),width:1),borderRadius:BorderRadius.circular(AppRadius.xl)),child:CustomPaint(painter:_ViewfinderPainter()))));}}
class _ViewfinderPainter extends CustomPainter{@override void paint(Canvas canvas,Size size){final paint=Paint()..color=Colors.white..strokeWidth=4..strokeCap=StrokeCap.round..style=PaintingStyle.stroke;const length=28.0;const radius=18.0;final path=Path()..moveTo(radius,0)..lineTo(length,0)..moveTo(0,radius)..lineTo(0,length)..moveTo(size.width-radius,0)..lineTo(size.width-length,0)..moveTo(size.width,radius)..lineTo(size.width,length)..moveTo(0,size.height-radius)..lineTo(0,size.height-length)..moveTo(radius,size.height)..lineTo(length,size.height)..moveTo(size.width-radius,size.height)..lineTo(size.width-length,size.height)..moveTo(size.width,size.height-radius)..lineTo(size.width,size.height-length);canvas.drawPath(path,paint);}@override bool shouldRepaint(covariant CustomPainter oldDelegate)=>false;}
class _ScannerCircleButton extends StatelessWidget{const _ScannerCircleButton({required this.icon,required this.tooltip,required this.onPressed});final IconData icon;final String tooltip;final VoidCallback onPressed;@override Widget build(BuildContext context)=>Tooltip(message:tooltip,child:Material(color:Colors.black.withValues(alpha:.48),shape:const CircleBorder(),child:InkWell(customBorder:const CircleBorder(),onTap:onPressed,child:SizedBox(width:46,height:46,child:Icon(icon,color:Colors.white)))));}
class _PermissionDeniedBody extends StatelessWidget{const _PermissionDeniedBody({required this.onEnterManually});final VoidCallback onEnterManually;@override Widget build(BuildContext context)=>Center(child:Padding(padding:const EdgeInsets.all(AppSpacing.xl),child:Column(mainAxisSize:MainAxisSize.min,children:[Container(width:72,height:72,decoration:BoxDecoration(color:Colors.white.withValues(alpha:.08),shape:BoxShape.circle),child:const Icon(FulusIcons.camera,color:Colors.white,size:34)),const SizedBox(height:AppSpacing.lg),Text('Camera access needed to scan',style:AppTypography.heading.copyWith(color:Colors.white),textAlign:TextAlign.center),const SizedBox(height:AppSpacing.sm),const Text('You can also type the barcode in by hand.',style:TextStyle(color:Colors.white70),textAlign:TextAlign.center),const SizedBox(height:AppSpacing.lg),FulusButton(label:'Enter barcode manually',onPressed:onEnterManually)])));}
