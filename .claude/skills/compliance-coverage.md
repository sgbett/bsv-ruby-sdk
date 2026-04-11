# Cross-SDK Compliance Review

## Problem

During development of the ruby SDK there was a period of time where /effort medium was the default setting.

### Manifestation

The consequences of insufficient effort are several issues that seemed to be due to a lack of rigour when analysing/re-implementing functionality that already exists in the typescript implementation; not recognising *why* some things were done a particular way. Of particular note 3 issues in https://github.com/sgbett/bsv-ruby-sdk/issues/305

The ruby SDK suffered from a systemic issue where we had been able to engineer code that passes all the tests but didn't quite implement the
desired functionality correctly. We created an SDK that follows "the letter" of the tests, rather than "the spirit" of the specification.

The swift implementation may also have been impacted by the use of /effort medium.

### Solution: The Thirty-Five.

I'd like you to orchestrate a team of agents that is composed of 10 project-level agents, and 8 triumvirates. One triumvirate for each of the 8 phases articulated in the plan /opt/xcode/bsv-sdk/.claude/plans/20260404-swift-bsv-sdk.md - each of these phases broadly scopes an area of concern in the code to focus on. Areas of overlap should be considered carefully as these boundaries likely correspond to the principle of "separation of concerns" we should try to ensure that there are clean lines such that each of the 8 phases cover different areas of the codebase with little to no overlap, A final agent should run alongside and independently audit which triumvirate covered which sections of code to establish any gaps or significant areas of overlap that may warrant refactoring. The triumvirate agents should answer any questions the auditor has, without interference from the project-level agents.

This makes a total of 10 + (8 * 3) + 1 = 35 agents.

## Project Level: 1 x 10 agents

10 "project-level" members based on the specialist definitions in the .architecture/members.yml file these agents are tasked with analysis of the findings reported by the triumverates.

### Findings Analysis

For each finding the 10 project-level team agents should deliberate on what action, if any, should be taken.

The level of agreement determines how the finding should be handled:

* <7 AGREE = SEVERE AMBIGUITY ‼️ - Isolate for seperate examination
* >7 AGREE = STRONG AGREE ✅ - Recommend action / No-Action, note disagreements
* ALL AGREE = UNILATERAL - Recommend action / No-Action

Where action is recommended this should be clearly documented as:
* Problem
* Proposed Solution
* Implementation Details
* Acceptance Crtieria

Where no action is recommended this should be clearly documented as:
* Potential Issue
* Reason for no-action

Where ambiguity exists this should be clearly documented as:
* Potential issues
* Reasons for action
* Reasons against action
* Areas for further exploration

## Triumverates: 8 x 3 agents

For each of the 8 phases there should be a 3 agents with combined responsibility as triumvirate, to validate alignment of our implementation with (in order of precedence):
* the typescript implementation
* corresponding BRC's
* other reference implementation
* any other documentation, specification discovered ad-hoc that may be relevant

Each triumverate should draw out areas where our deviation may have introduced subtle bugs or incompatibilities. Each "Finding" should be assessed by the project level agents as a group to validate it and confirm the actions to be taken.

### Agent Roles

Within each triumvirate each agent has a specific focus:

#### Agent #phase-#1-dev - A developer, ruby & typescript expert, master of implementation.
This agent should focus on qualitative difference in implementation between ruby and ts (using go/python as secondary sources) identifying code that needs to be changed and why.

#### Agent #phase-#2-docs - A domain specialist, detail focused, thorough.
Conduct a deep dive on the documentation and available specifications, seeking out supplementary material on the internet for clarification if needed. The BRC's should be considered authoritative, any other documentation (e.g. in the ts-sdk, or published by the BSVA in their reference docs etc) used to corroborate. This agent should be able to answer any questions any other agent might have on implementation details.

#### Agent #phase-#3-truth - A mediator, logician, a seeker of truth.
Cross-checks the other two agents work, offering alternative viewpoints, identifying ambiguity between implementation and documentation and surfacing issues. This agent may identify tension or ambiguity that exists in the reference material itself that could lead to misinterpretation - this should be raised as a point of critical concern for resolution before any attempt to resolve.

### The Auditor
Meticulous, relentless
By the end of the excercise, this guy knows **exactly** who is responsible for every bit of code.

#### Coverage Flags
The auditor is seeking to ensure we have cood **Compliance** coverage. This could be considered analagous to test coverage.

**Complaince** is achevied when a triumverates gives attention to the inner workings of "func" calls, particularly where they are checking that this matches the reference implementation, analysis of why code works the way it does.
**Usage** is when a triumverate looks at code because it needs to now how to use it, what results to expect, but is not concnered with how those results are obtained, or where concern for that is tangential to the momentary anlaysis.
**Overlap** is where more than one triumverate is looking at code for **Compliance** purposes. **Usage** does not trigger overlap.
**Gaps** is where no single triumverate looks at code for **Compliance**. **Usage** does not obiate gaps.

Both **Overlap** or **Gaps** may be indicative of an underlying design issue with regards scoping concern, and warrant seperate investigation.

#### Compliance Coverage
The auditor should produce their own supplementary report on  coverage across the codebase. A high level summary using a traffic light system, three percentage values:

* GREEN: % Compliance
* YELLOW: % Overlap
*RED: % Gaps

A very breif summary of Compliance, a single paragraph with key areas covered, followed by detailed sections for each logical cluster of overlap and/or gaps.

The auditor doeas not need validation from the project-level team, their findings should not be veto's they are an independant auditor.

## Summary

Orchestrate as a single team. All agents *can* confer if necessary, but *should* remain focused primilary on their area of concern, within their defined role. 80/20 rules.

This is a complex task, allow all the agents max effort.
