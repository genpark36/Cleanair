import numpy as np
import plotly.graph_objects as go
from plotly.subplots import make_subplots


# 1. IAQI 로직 (기존 결함 버전 유지)
class FlawedIAQILogic:
    def __init__(self):
        self.bps = {
            "co2": ([420, 1000, 1500, 2500, 5000], [0, 50, 100, 200, 500]),
            "pm25": ([0, 15, 35, 75, 150], [0, 50, 100, 200, 500]),
            "tvoc": ([0, 200, 500, 1500, 3000], [0, 50, 100, 200, 500]),
            "nox": ([0, 0.03, 0.06, 0.2, 2.0], [0, 50, 100, 200, 500]),
        }

    def get_sub_index(self, val, pollutant):
        bp, ip = self.bps[pollutant]
        return np.interp(val, bp, ip)

    def calculate(self, co2, pm25, tvoc, nox):
        indices = [
            self.get_sub_index(co2, "co2"),
            self.get_sub_index(pm25, "pm25"),
            self.get_sub_index(tvoc, "tvoc"),
            self.get_sub_index(nox, "nox"),
        ]
        i_max = max(indices)
        i_avg = sum(indices) / len(indices)
        k = np.clip((i_max - 90) / 20, 0, 1)
        iaqi_weighted = sum(indices) / 4
        iaqi_rss = np.sqrt((i_max**2 + i_avg**2) / 2)
        iaqi_final = (1 - k) * iaqi_weighted + k * iaqi_rss
        iaqi_final = max(iaqi_final, i_max)
        return iaqi_final, i_max, indices


# 2. 데이터 생성
logic = FlawedIAQILogic()
steps = 600
np.random.seed(15)


def generate_sensor_data(start, scale, steps):
    return start + np.cumsum(np.random.normal(0, scale, steps))


co2_raw = np.clip(generate_sensor_data(1300, 25, steps), 420, 2500)
pm25_raw = np.clip(generate_sensor_data(30, 1.5, steps), 0, 80)
tvoc_raw = np.clip(generate_sensor_data(450, 15, steps), 0, 1000)
nox_raw = np.clip(generate_sensor_data(0.04, 0.003, steps), 0, 0.15)

iaqi_hist, imax_hist, sub_hist = [], [], []
for i in range(steps):
    res, imax, sub = logic.calculate(co2_raw[i], pm25_raw[i], tvoc_raw[i], nox_raw[i])
    iaqi_hist.append(res)
    imax_hist.append(imax)
    sub_hist.append(sub)

sub_hist = np.array(sub_hist)

# 3. Plotly 반응형 그래프 생성
fig = make_subplots(
    rows=2,
    cols=1,
    shared_xaxes=True,
    vertical_spacing=0.1,
    subplot_titles=(
        "1. Individual Pollutant Sub-indices (Click Legend to Toggle)",
        "2. Integrated IAQI Logic Response",
    ),
)

# --- 상단 그래프 (Sub-indices) ---
names = ["CO2 Index", "PM2.5 Index", "TVOC Index", "NOx Index"]
colors = ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728"]

for i in range(4):
    fig.add_trace(
        go.Scatter(
            y=sub_hist[:, i],
            name=names[i],
            mode="lines",
            line=dict(color=colors[i], width=1.5),
            opacity=0.7,
        ),
        row=1,
        col=1,
    )

# 위험 전환 구간 표시 (노란색 영역)
fig.add_hrect(y0=90, y1=110, fillcolor="yellow", opacity=0.1, line_width=0, row=1, col=1)

# --- 하단 그래프 (IAQI) ---
fig.add_trace(
    go.Scatter(y=iaqi_hist, name="Integrated IAQI", mode="lines", line=dict(color="black", width=3)),
    row=2,
    col=1,
)
fig.add_trace(
    go.Scatter(y=imax_hist, name="I_max (Reference)", mode="lines", line=dict(color="gray", width=1, dash="dash")),
    row=2,
    col=1,
)

# 레이아웃 설정
fig.update_layout(
    height=800,
    title_text="IAQI Interactive Stress Test Simulator",
    hovermode="x unified",  # 마우스를 올리면 같은 시간대의 모든 수치 표시
    showlegend=True,
)

fig.update_yaxes(title_text="Index Value", row=1, col=1)
fig.update_yaxes(title_text="IAQI Value", row=2, col=1)

# 그래프 실행
fig.show()
