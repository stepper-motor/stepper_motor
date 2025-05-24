# StepperMotor

Is a useful tool for running stepped or iterative workflows inside your Rails application.

## Usage

Define a workflow and launch your user into it:

```ruby
class SignupJourney < StepperMotor::Journey
  step :after_signup do
    WelcomeMailer.welcome_email(hero).deliver_later
  end

  step :remind_of_tasks, wait: 2.days do
    ServiceUpdateMailer.two_days_spent_email(hero).deliver_later
  end

  step :onboarding_complete, wait: 15.days do
    OnboardingCompleteMailer.onboarding_complete_email(hero).deliver_later
  end
end

SignupJourney.create!(hero: current_user)
```

## Installation

Add the gem to the application's Gemfile, and then generate and run the migration

    $ bundle add stepper_motor
    $ bundle install
    $ bin/rails g stepper_motor:install --uuid # Pass "uuid" if you are using UUID for your primary and foreign keys
    $ bin/rails db:migrate

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Is it any good?

[Yes.](https://news.ycombinator.com/item?id=3067434)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/stepper-motor/stepper_motor.
