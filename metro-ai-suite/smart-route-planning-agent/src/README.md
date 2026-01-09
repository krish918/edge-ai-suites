# Smart Route Planning Agent

| **STATUS** |  Work in Progress |
|------------| ------------------|

A sophisticated Gradio-based web application that demonstrates dynamic route planning using agentic AI. The application integrates real GPX route data with multiple simulated data sources (weather, traffic, forest fire alerts) to determine optimal routes with a comprehensive visual thinking process.

## Features

- **Interactive Web Interface**: Modern Gradio-based UI with progressive web app (PWA) support
- **Real GPX Route Integration**: Uses actual GPX files with waypoints and track data for realistic route visualization
- **Agentic AI Thinking Process**: Comprehensive visual representation of the AI agent's decision-making process
- **Multiple Data Sources**: Simulated MCP (Model Context Protocol) servers for:
  - Weather conditions analysis
  - Traffic congestion and incident detection
  - Forest fire alerts and environmental hazards
- **Dynamic Route Switching**: Automatically overlays alternative routes based on detected conditions
- **Real-time Progress Visualization**: Multi-step progress tracking with detailed thinking output
- **Advanced Map Integration**: Folium-based maps with multiple route overlays, markers, and route information
- **Modular Architecture**: Clean separation of concerns with services, utilities, and data models
- **Comprehensive Logging**: Full application logging with configurable levels
