import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const Home(),
    ));

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final keyCtrl = TextEditingController();
  String? videoPath;
  String videoName = 'Koi video nahi chuni';
  bool loop = true;
  bool fast = false;
  String quality = '720';
  bool running = false;
  bool hideKey = true;
  String elapsed = '00:00:00';
  final List<String> logs = [];

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      setState(() {
        keyCtrl.text = p.getString('key') ?? '';
        loop = p.getBool('loop') ?? true;
        fast = p.getBool('fast') ?? false;
        quality = p.getString('quality') ?? '720';
      });
    });
  }

  Future<void> saveSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('key', keyCtrl.text.trim());
    await p.setBool('loop', loop);
    await p.setBool('fast', fast);
    await p.setString('quality', quality);
  }

  void addLog(String s) {
    final key = keyCtrl.text.trim();
    if (key.isNotEmpty) s = s.replaceAll(key, '****');
    s = s.trim();
    if (s.isEmpty || !mounted) return;
    setState(() {
      logs.add(s);
      if (logs.length > 40) logs.removeAt(0);
    });
  }

  void toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> pickVideo() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.video);
    if (r != null && r.files.single.path != null) {
      setState(() {
        videoPath = r.files.single.path;
        videoName = r.files.single.name;
      });
    }
  }

  String fmt(int secs) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(secs ~/ 3600)}:${two((secs % 3600) ~/ 60)}:${two(secs % 60)}';
  }

  Future<void> start() async {
    final key = keyCtrl.text.trim();
    if (videoPath == null) return toast('Pehle video chuno');
    if (key.isEmpty) return toast('Stream key daalo');
    await saveSettings();

    final args = <String>['-re'];
    if (loop) args.addAll(['-stream_loop', '-1']);
    args.addAll(['-i', videoPath!]);
    if (fast) {
      args.addAll(['-c', 'copy']);
    } else {
      final br = {'480': 1200, '720': 2500, '1080': 4500}[quality]!;
      args.addAll([
        '-vf', 'scale=-2:$quality', '-r', '30', '-g', '60',
        '-c:v', 'libx264', '-preset', 'veryfast', '-pix_fmt', 'yuv420p',
        '-b:v', '${br}k', '-maxrate', '${br}k', '-bufsize', '${br * 2}k',
        '-c:a', 'aac', '-b:a', '128k', '-ar', '44100',
      ]);
    }
    args.addAll(['-f', 'flv', 'rtmp://a.rtmp.youtube.com/live2/$key']);

    setState(() {
      running = true;
      logs.clear();
      elapsed = '00:00:00';
    });
    await WakelockPlus.enable();
    addLog('Stream shuru ho rahi hai...');

    await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) async {
        final rc = await session.getReturnCode();
        await WakelockPlus.disable();
        if (!mounted) return;
        setState(() => running = false);
        if (ReturnCode.isSuccess(rc)) {
          addLog('Video khatam, stream band ho gayi.');
        } else if (ReturnCode.isCancel(rc)) {
          addLog('Stream aap ne band ki.');
        } else {
          addLog('Stream ruk gayi (error). Upar ke log dekho. Stream key aur internet check karo.');
        }
      },
      (log) => addLog(log.getMessage()),
      (stat) {
        final t = stat.getTime();
        if (t > 0 && mounted) setState(() => elapsed = fmt((t / 1000).floor()));
      },
    );
  }

  Future<void> stop() async {
    await FFmpegKit.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📡 YouTube Live Streamer')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(running ? '🟢 LIVE chal rahi hai' : '🔴 Band hai',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              if (running) Text('Chalte hue: $elapsed'),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: running
                    ? FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: stop,
                        child: const Text('⏹ Stop'))
                    : FilledButton(onPressed: start, child: const Text('▶ Start Stream')),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('1. Video', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(videoName),
              OutlinedButton(
                  onPressed: running ? null : pickVideo,
                  child: const Text('Video chuno')),
              const SizedBox(height: 14),
              const Text('2. YouTube Stream Key', style: TextStyle(fontWeight: FontWeight.bold)),
              TextField(
                controller: keyCtrl,
                enabled: !running,
                obscureText: hideKey,
                decoration: InputDecoration(
                  hintText: 'YouTube Studio se copy karke paste karo',
                  suffixIcon: IconButton(
                    icon: Icon(hideKey ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => hideKey = !hideKey),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('3. Quality', style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                value: quality,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: '480', child: Text('480p (kam data, halka)')),
                  DropdownMenuItem(value: '720', child: Text('720p HD')),
                  DropdownMenuItem(value: '1080', child: Text('1080p Full HD (tez phone chahiye)')),
                ],
                onChanged: running || fast ? null : (v) => setState(() => quality = v!),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Loop (baar baar chale)'),
                subtitle: const Text('OFF karo to video khatam hote hi stream band'),
                value: loop,
                onChanged: running ? null : (v) => setState(() => loop = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fast mode'),
                subtitle: const Text('Sirf tab jab video H.264/AAC ho. Phone kam garam hota hai'),
                value: fast,
                onChanged: running ? null : (v) => setState(() => fast = v),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Log', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                logs.isEmpty ? '-' : logs.reversed.take(8).toList().reversed.join('\n'),
                style: const TextStyle(fontSize: 11),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Dhyan: stream chalte waqt app khuli rakho aur internet on rakho. Screen apne aap on rehti hai.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ]),
    );
  }
}
