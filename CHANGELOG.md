# 0.12.2 - 11-09-2019

- Allow sorting schedule history by schedule name

# 0.12.1 - 30-08-2019

- Jobs that change family from per host to non per host can cause a tight loop

# 0.12.0 - 29-08-2019

- Add support for multiple workers which allows avoiding queue starvation

# 0.11.0 - 24-06-2019

- Correct situation where distributed mutex could end in a tight loop when
 redis could not be contacted

# 0.9.2 - 26-04-2019

- Correct UI so it displays durations that are longer than a minute

# 0.9.1 - 21-01-2019

- Remove dependency on ActiveSupport and add proper dependency for Sidekiq
- Remove Discourse specific bits from Sidekiq web scheduler tab.
