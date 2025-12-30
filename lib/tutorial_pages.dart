import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'demo_page.dart';

class TutorialPages extends StatefulWidget {
  const TutorialPages({super.key});

  @override
  State<TutorialPages> createState() => _TutorialPagesState();
}

class _TutorialPagesState extends State<TutorialPages> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> pages = [
    {
      "title": "SOS Function",
      "bullets": [
        "📹 Record a short video instantly using your front camera.",
        "📍 Capture your exact location automatically.",
        "⚡ Upload the video and location to Supabase for immediate help.",
      ],
      "image": "lib/assets/images/tutorial_sos.png", // ✅ corrected path
    },
    {
      "title": "Report Function",
      "bullets": [
        "📝 Submit detailed reports directly from the app.",
        "📊 Track the status of your reports in real-time.",
        "🔔 Get notified when your report is updated or resolved.",
      ],
      "image": "lib/assets/images/tutorial_report.png", // ✅ corrected path
    },
    {
      "title": "Volume Button SOS",
      "bullets": [
        "🔊 Press the volume button 4 times quickly.",
        "🚨 Instantly trigger the SOS function without opening the app.",
        "✅ Works seamlessly when the app is running in the background.",
      ],
      "image": "lib/assets/images/tutorial_volume.png", // ✅ corrected path
    },
  ];

  Future<void> _finishTutorial() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId != null) {
      await supabase
          .from('student_details')
          .update({'seen_tutorial': true})
          .eq('user_id', userId);
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Demopage1()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  final page = pages[index];
                  return Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          page["image"]!,
                          height: 200,
                          width: 200,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 40),
                        Text(
                          page["title"]!,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontFamily: 'Inter',
                            color: theme.primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 30),
                        // ✅ Rounded card for info
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: (page["bullets"] as List<String>)
                                  .map((bullet) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        child: Text(
                                          bullet,
                                          style: theme.textTheme.bodyLarge
                                              ?.copyWith(
                                            fontFamily: 'Inter',
                                            fontSize: 18, // ✅ larger font
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // ✅ Dots indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                pages.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 12 : 8,
                  height: _currentPage == index ? 12 : 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? theme.primaryColor
                        : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // ✅ Proceed button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(55),
                  backgroundColor: _currentPage == pages.length - 1
                      ? const Color.fromARGB(255, 247, 67, 67) // ✅ soft pink
                      : Colors.grey.shade400,
                  textStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22, // ✅ larger font
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                onPressed: _currentPage == pages.length - 1
                    ? _finishTutorial
                    : null,
                child: const Text(
                  "Proceed to App",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22, // ✅ larger font
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}