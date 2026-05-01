import 'dart:ui';
import 'package:flutter/material.dart';

void main() => runApp(const WeatherPrototypeApp());

class WeatherPrototypeApp extends StatelessWidget {
  const WeatherPrototypeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark),
      home: const WeatherHomeScreen(),
    );
  }
}

class WeatherHomeScreen extends StatelessWidget {
  const WeatherHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // [1] 날씨에 따라 다이나믹하게 변하는 백그라운드 그라데이션
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3B82F6), Color(0xFF1E3A8A)], // 맑은 날씨 파란색 테마
          ),
        ),
        // [2] 네이티브 앱의 CoordinatorLayout 완벽 대체제
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(), // 부드러운 스크롤 바운스 (iOS/OneUI 스타일)
          slivers: [
            
            // [3] 슬라이드 다운 시 나타나고 접히는 동적 헤더 (SliverAppBar)
            SliverAppBar(
              expandedHeight: 280.0, // 완전히 펼쳐졌을때의 높이
              floating: false,
              pinned: true,       // 스크롤 올려도 상단바만 요약되어 남게 하기
              backgroundColor: Colors.transparent, // 투명하게 해서 뒤 레이아웃 비치게 만듦
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                centerTitle: true,
                titlePadding: const EdgeInsets.only(bottom: 16),
                title: const Text(
                  '대구광역시 영남대',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white),
                ),
                background: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    SizedBox(height: 40),
                    // 온도 및 헬스 스코어가 가장 크게 들어가는 메인 영역
                    Text('21', style: TextStyle(fontSize: 80, fontWeight: FontWeight.w200, color: Colors.white, height: 1.0)),
                    Text('실내 공기질 훌륭함', style: TextStyle(fontSize: 20, color: Colors.white70)),
                    SizedBox(height: 8),
                    Text('최고 25 최고점수 90점', style: TextStyle(fontSize: 14, color: Colors.white70)),
                  ],
                ),
              ),
            ),

            // [4] 유리 질감 컴포넌트 리스트들 (SliverList)
            SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 16),
                _buildGlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('시간별 날씨 & 공기질 (추이)', style: TextStyle(fontSize: 14, color: Colors.white70)),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 10),
                      // 가로 스크롤 뷰 구현
                      SizedBox(
                        height: 100,
                        child: ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          scrollDirection: Axis.horizontal,
                          itemCount: 12, // 임시 데이터 12개
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: Column(
                                children: [
                                  Text('${index + 1}시', style: const TextStyle(color: Colors.white, fontSize: 13)),
                                  const SizedBox(height: 10),
                                  const Icon(Icons.wb_cloudy_rounded, color: Colors.white, size: 28),
                                  const SizedBox(height: 10),
                                  const Text('20', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                
                _buildGlassCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('실내 PM2.5', style: TextStyle(color: Colors.white54, fontSize: 13)),
                            SizedBox(height: 4),
                            Text('12 µg/m', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                          ]
                        )
                      ),
                      Container(width: 1, height: 50, color: Colors.white24),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('야외 미세먼지', style: TextStyle(color: Colors.white54, fontSize: 13)),
                              SizedBox(height: 4),
                              Text('35 µg/m', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                            ]
                          ),
                        )
                      ),
                    ],
                  )
                ),

                _buildGlassCard(height: 200, child: const Center(child: Text("상세 공기질 / 습도 카드", style: TextStyle(color: Colors.white)))),
                _buildGlassCard(height: 200, child: const Center(child: Text("생활 지수 (빨래, 환기 등) 카드", style: TextStyle(color: Colors.white)))),
                const SizedBox(height: 60), // 맨아래 여백
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // [5] 네이티브 앱의 CardView + 반투명 블러 효과 구현 (Glassmorphism)
  Widget _buildGlassCard({required Widget child, double? height}) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20), // 둥근 모서리
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0), // 내부 화면 흐리게 만들기 (블러)
          child: Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white.withOpacity(0.15), // 반투명 흰색 덧씌우기
            child: child,
          ),
        ),
      ),
    );
  }
}
