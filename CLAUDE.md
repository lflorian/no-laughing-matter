# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Title: "Who's Laughing Now? – A Computational Analysis of Parliamentary Humor in Germany"
Goal: Analyze humor patterns in German Bundestag parliamentary protocols to understand when, how, and why laughter occurs in parliamentary debate, and what political or communicative functions it serves.
Research Question: How, when and why is there laughter in the German Bundestag – and what political or communicative functions does this laughter fulfill?
For achieving this goal, we are developing "no laughing matter" – a macOS SwiftUI application for analyzing political humor in protocols of the German Bundestag. It uses Apple's FoundationModels framework to classify the intention behind humor in parliamentary contexts.

## Build & Run

- **Open in Xcode:** `open "no laughing matter.xcodeproj"`
- **Build:** Cmd+B or `xcodebuild -scheme "no laughing matter"`
- **Run:** Cmd+R in Xcode
- **Platform:** macOS 26.1+ required (uses FoundationModels framework)

## Architecture

**Pattern:** MVVM with service layer

**Key Components:**
- `ContentView.swift` - Main UI with text input and results display
- `IntelligenceManager.swift` - Singleton service managing LLM session and prompt construction
- `LLMClassification.swift` - Response model using `@Generable` macro with `@Guide` annotations for structured LLM output
- `Event.swift` - Domain model (scaffolded for future use)

## Technical Details

The program will use a three-phase processing pipeline.

### Phase 1: Parsing and Deterministic Data Preparation
#### Purpose: Extract structured data from XML protocol files
#### Process:
- Fetch protocols from Bundestag public API (XML format)
- The API would be: https://www.bundestag.de/services/opendata
- Use regex-based parsing to identify humor markers:
    - "Heiterkeit" (general amusement)
    - "Gelächter" (laughter)
    - other variations
- Extract surrounding context for each humor event
- Capture metadata (Speaker name, party/fraction, session date and number, legislative period, topic/agenda item)
- Store as HumorEvent


### Phase 2: NLP-based Contextual Classification
#### Purpose: Classify the type and intention of each humor event using LLM analysis
#### Process:
- For each HumorEvent, construct a prompt with: Surrounding text content, speaker information, political context (session topic)
- Use FoundationModels API to classify
- Classification uses Avner Ziv's (1984) five-functions model of humor (aggressive, social, defensive, intellectual, sexual), plus unclear (insufficient context). Each event receives a primary intention and an optional secondary intention.
- The LLM should output confidence rating about its classification, results with a low confidence should be discarded


### Phase 3: Quantitative and Qualitative Analysis
#### Purpose: Generate insights through statistical analysis and visualization
#### Possible Analyses:
- (1) Temporal Trends
    - Humor frequency over time (by legislative period)
    - Changes before/after AfD entry (2017)
    - Seasonal patterns within legislative periods
- (2) Actor Analysis
    - Which parties/factions are most often source or target of humour
    - Which individual Members of Parliament are most often source or target of humour
    - Demographic patterns (age, gender, region)
    - Heatmap Pattern on the seating layout (which "seats" laugh the most, visualization idea)
    - Note: More detailed information about the speaker will be necessary, there is an XML table with all speakers. Will discuss and implement this at a later point. Remind me.
- (3) Humor Type Distribution
    - Prevalance of different humor types by party
    - Evolution of humor styles over time
    - Correlation between humor type and political context (e.g. topic of session)
- (4) Network Analysis
    - Who laughs at whom?
    - Solidarity patterns within/between parties

#### Visualization Approach:
- Swift Charts should be used as a framework

#### Storage:
- I am unsure about the best storage solution. Might SwiftData be good?


## Possible Challenges
- Inconsistent Protocol Formatting, Humor markers might vary in phrasing -> Solution: flexible regex patterns
- Context dependency -> Solution: Provide rich context in prompts, manual validation of samples
