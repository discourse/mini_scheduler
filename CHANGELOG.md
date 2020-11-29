# 0.13.0 - 2020-11-30

- Fix exception code so it has parity with Sidekiq 4.2.3 and up, version bump cause
minimum version of Sikekiq changed.

# 0.12.3 - 2020-10-15

- Fixes a problem where scheduler didn't recover from Redis flush

# 0.12.2 - 2019-09-11

- Allow sorting schedule history by schedule name

# 0.12.1 - 2019-08-30

- Jobs that change family from per host to non per host can cause a tight loop

# 0.12.0 - 2019-08-29

- Add support for multiple workers which allows avoiding queue starvation

# 0.11.0 - 2019-06-24

- Correct situation where distributed mutex could end in a tight loop when
 redis could not be contacted

# 0.9.2 - 2019-04-26

- Correct UI so it displays durations that are longer than a minute

# 0.9.1 - 2019-01-21

- Remove dependency on ActiveSupport and add proper dependency for Sidekiq
- Remove Discourse specific bits from Sidekiq web scheduler tab.
