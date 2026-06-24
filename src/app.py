import pandas as pd
import streamlit as st

from alerts import check_threshold, publish_alert
from checker import check_all
from logging_config import configure_logging
from targets import load_targets

configure_logging()

st.set_page_config(page_title="Net-Infra-Monitor", layout="wide")

st.sidebar.header("Configuration")
threshold = st.sidebar.slider("Latency Threshold (ms)", 50, 2000, 300)
alerts_enabled = st.sidebar.checkbox("Send SNS alerts on breach", value=False)

st.sidebar.markdown("---")
st.sidebar.caption(
    "Targets are real infrastructure provisioned by Terraform "
    "(see terraform/). Edit config/nodes.json to point this at "
    "your own resources."
)


@st.cache_data(ttl=10)
def get_node_data(threshold_ms: float) -> pd.DataFrame:
    targets = load_targets()
    results = check_all(targets)

    df = pd.DataFrame([r.__dict__ for r in results])
    df["Status"] = df.apply(
        lambda row: "Warning"
        if check_threshold(row["latency_ms"], threshold_ms, row["reachable"])
        else "Online",
        axis=1,
    )
    df = df.rename(
        columns={
            "name": "Node",
            "target": "Target",
            "latency_ms": "Latency (ms)",
            "reachable": "Reachable",
            "error": "Error",
        }
    )
    return df


st.title("Net-Infra-Monitor")

try:
    data = get_node_data(threshold)
except FileNotFoundError as e:
    st.error(str(e))
    st.stop()

if not data.empty:
    col1, col2, col3 = st.columns(3)
    col1.metric("Total Nodes", len(data))
    warning_count = len(data[data["Status"] == "Warning"])
    col2.metric("Active Alerts", warning_count)
    online_pct = (len(data[data["Status"] == "Online"]) / len(data)) * 100
    col3.metric("System Health", f"{online_pct:.0f}%")

    if alerts_enabled and warning_count > 0:
        breached = data[data["Status"] == "Warning"]["Node"].tolist()
        publish_alert(f"Threshold breach on: {', '.join(breached)}")

    st.write("### Current Node Status")

    def color_status(row):
        color = "#8B0000" if row["Status"] == "Warning" else "#006400"
        return [f"background-color: {color}; color: white"] * len(row)

    st.dataframe(data.style.apply(color_status, axis=1), use_container_width=True)

    st.write("### Latency by Node")
    chart_data = data.dropna(subset=["Latency (ms)"]).set_index("Node")["Latency (ms)"]
    if not chart_data.empty:
        st.bar_chart(chart_data)
    else:
        st.info("No reachable nodes to chart.")

    if st.button("Refresh Now"):
        st.cache_data.clear()
        st.rerun()
else:
    st.warning("No targets configured. Add entries to config/nodes.json.")
