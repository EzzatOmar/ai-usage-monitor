# AI Usage Monitor - TODO

## Completed

### Cerebras Usage Monitoring
- [x] Research how to get actual usage/quota data from Cerebras API
- [x] Test if `/v1/models` endpoint returns `x-ratelimit-*` headers (NO - doesn't return them)
- [x] Switch to minimal chat completion (`max_completion_tokens: 1`) to get headers
- [x] Write test for Cerebras usage fetch (tests exist in ProviderDecodingTests.swift)
- [x] Add 402 payment required error handling
- [x] Use `zai-glm-4.7` model (works on all tiers)
- [x] Add UI note about ~10K tokens/day probe technique

## Medium Priority

### Code Quality
- [ ] Add more unit tests for edge cases
- [ ] Add integration tests for API responses

## Low Priority

### Future Enhancements
- [ ] Consider adding more providers (Cursor, etc.)
- [ ] Add notification support (optional)
- [ ] Add preference window for poll interval
