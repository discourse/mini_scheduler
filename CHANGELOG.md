# 0.11.0 - 24-06-2019

- Correct situation where distributed mutex could end in a tight loop when
 redis could not be contacted

# 0.9.2 - 26-04-2019

- Correct UI so it displays durations that are longer than a minute

# 0.9.1 - 21-01-2019

- Remove dependency on ActiveSupport and add proper dependency for Sidekiq
- Remove Discourse specific bits from Sidekiq web scheduler tab.
