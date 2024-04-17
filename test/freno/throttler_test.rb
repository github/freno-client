# frozen_string_literal: true

require "test_helper"

class FrenoThrottlerTest < ThrottlerTest
  def test_validations
    ex = assert_raises(ArgumentError) do
      Freno::Throttler.new(wait_seconds: 1, max_wait_seconds: 0.5)
    end
    assert_includes ex.message, "app must be provided"
    assert_includes ex.message, "client must be provided"
    assert_includes ex.message, "max_wait_seconds (0.5) has to be greather than wait_seconds (1)"
  end

  def test_using_the_default_identity_mapper
    block_called = false

    stub = sample_client
    stub.expects(:check?).once
      .with(app: :github, store_name: :mysqla, options: {})
      .returns(true)

    throttler = Freno::Throttler.new(client: stub, app: :github)

    throttler.throttle(:mysqla) do
      block_called = true
    end

    assert block_called, "block should have been called"
  end

  def test_throttle_checks_with_low_priority
    block_called = false

    stub = sample_client
    stub.expects(:check?).once
      .with(app: :github, store_name: :mysqla, options: { low_priority: true })
      .returns(true)

    throttler = Freno::Throttler.new(client: stub, app: :github)

    throttler.throttle(:mysqla, low_priority: true) do
      block_called = true
    end

    assert block_called, "block should have been called"
  end

  def test_throttle_runs_the_block_when_all_stores_have_caught_up
    block_called = false

    throttler = Freno::Throttler.new do |t|
      t.client = sample_client
      t.app = :github
      t.mapper = ->(_context) { [] }
      t.instrumenter = MemoryInstrumenter.new
    end

    throttler.throttle(:wadus) do
      block_called = true
    end

    assert block_called, "block should have been called"

    assert_equal 1, throttler.instrumenter.count("throttler.called")
    assert_empty throttler.instrumenter.events_for("throttler.called")
                   .first[:store_names]

    assert_equal 1, throttler.instrumenter.count("throttler.succeeded")
    assert_empty throttler.instrumenter.events_for("throttler.succeeded")
                   .first[:store_names]

    assert_equal 0, throttler.instrumenter.count("throttler.waited")
    assert_equal 0, throttler.instrumenter.count("throttler.waited_too_long")
    assert_equal 0, throttler.instrumenter.count("throttler.freno_errored")
    assert_equal 0, throttler.instrumenter.count("throttler.circuit_open")
  end

  def test_sleeps_when_a_check_fails_and_then_calls_the_block
    block_called = false

    stub = sample_client
    stub.expects(:check?).times(2)
      .with(app: :github, store_name: :mysqla, options: {})
      .returns(false).then.returns(true)

    throttler = Freno::Throttler.new do |t|
      t.client = stub
      t.app = :github
      t.mapper = ->(_context) { [:mysqla] }
      t.instrumenter = MemoryInstrumenter.new
    end
    throttler.expects(:wait).once.returns(0.1)

    throttler.throttle do
      block_called = true
    end

    assert block_called, "block should have been called"

    called_events = throttler.instrumenter.events_for("throttler.called")

    assert_equal 1, called_events.count
    assert_equal [:mysqla], called_events.first[:store_names]

    waited_events = throttler.instrumenter.events_for("throttler.waited")

    assert_equal 1, waited_events.count
    assert_equal [:mysqla], waited_events.first[:store_names]
    assert_in_delta 0.5, waited_events.first[:waited], 0.01
    assert_equal 10, waited_events.first[:max]

    assert_equal 0, throttler.instrumenter.count("throttler.waited_too_long")
    assert_equal 0, throttler.instrumenter.count("throttler.freno_errored")
    assert_equal 0, throttler.instrumenter.count("throttler.circuit_open")
  end

  def test_raises_waited_too_long_if_freno_checks_failed_consistenly
    block_called = false

    stub = sample_client
    stub.expects(:check?).at_least(3)
      .with(app: :github, store_name: :mysqla, options: {})
      .returns(false)

    throttler = Freno::Throttler.new do |t|
      t.client = stub
      t.app = :github
      t.mapper = ->(_context) { [:mysqla] }
      t.instrumenter = MemoryInstrumenter.new
      t.wait_seconds = 0.1
      t.max_wait_seconds = 0.3
    end

    throttler.expects(:wait).times(3).returns(0.1)

    assert_raises(Freno::Throttler::WaitedTooLong) do
      throttler.throttle do
        block_called = true
      end
    end

    refute block_called, "block should not have been called"

    assert_equal 1, throttler.instrumenter.count("throttler.called")
    assert_equal 0, throttler.instrumenter.count("throttler.succeeded")
    assert_equal 3, throttler.instrumenter.count("throttler.waited")

    waited_too_long_events =
      throttler.instrumenter.events_for("throttler.waited_too_long")

    assert_equal 1, waited_too_long_events.count
    assert_equal [:mysqla], waited_too_long_events.first[:store_names]
    assert_in_delta 0.3, waited_too_long_events.first[:max], 0.01
    assert_operator waited_too_long_events.first[:waited], :>=, 0.3

    assert_equal 0, throttler.instrumenter.count("throttler.freno_errored")
    assert_equal 0, throttler.instrumenter.count("throttler.circuit_open")
  end

  def test_raises_a_specific_error_in_case_freno_itself_errored
    block_called = false

    stub = sample_client
    stub.expects(:check?).raises(Freno::Error)

    throttler = Freno::Throttler.new do |t|
      t.client = stub
      t.app = :github
      t.mapper = ->(_context) { [:mysqla] }
      t.instrumenter = MemoryInstrumenter.new
      t.wait_seconds = 0.1
      t.max_wait_seconds = 0.3
    end

    throttler.expects(:wait).never

    assert_raises(Freno::Throttler::ClientError) do
      throttler.throttle do
        block_called = true
      end
    end

    refute block_called, "block should not have been called"

    assert_equal 1, throttler.instrumenter.count("throttler.called")
    assert_equal 0, throttler.instrumenter.count("throttler.succeeded")
    assert_equal 0, throttler.instrumenter.count("throttler.waited")
    assert_equal 0, throttler.instrumenter.count("throttler.waited_too_long")

    freno_errored_events =
      throttler.instrumenter.events_for("throttler.freno_errored")

    assert_equal 1, freno_errored_events.count
    assert_equal [:mysqla], freno_errored_events.first[:store_names]
    assert_kind_of Freno::Error, freno_errored_events.first[:error]

    assert_equal 0, throttler.instrumenter.count("throttler.circuit_open")
  end

  def test_circuit_breaker
    block_called = false

    stub = sample_client
    stub.expects(:check?).raises(Freno::Error)

    throttler = Freno::Throttler.new do |t|
      t.client = stub
      t.app = :github
      t.mapper = ->(_context) { [:mysqla] }
      t.instrumenter = MemoryInstrumenter.new
      t.circuit_breaker = SingleFailureAllowedCircuitBreaker.new
    end

    assert_raises(Freno::Throttler::ClientError) do
      throttler.throttle do
        block_called = true
      end
    end

    refute block_called, "block should not have been called"

    assert_raises(Freno::Throttler::CircuitOpen) do
      throttler.throttle do
        block_called = true
      end
    end

    refute block_called, "block should not have been called"

    assert_equal 2, throttler.instrumenter.count("throttler.called")
    assert_equal 0, throttler.instrumenter.count("throttler.succeeded")
    assert_equal 0, throttler.instrumenter.count("throttler.waited")
    assert_equal 0, throttler.instrumenter.count("throttler.waited_too_long")
    assert_equal 1, throttler.instrumenter.count("throttler.freno_errored")

    circuit_breaker_events =
      throttler.instrumenter.events_for("throttler.circuit_open")

    assert_equal 1, circuit_breaker_events.count
    assert_equal [:mysqla], circuit_breaker_events.first[:store_names]
    assert_equal 0, circuit_breaker_events.first[:waited]
  end

  def test_throttles_an_enumerator
    array = [1, 2, 3]
    enumerator = array.each
    result = []

    throttler = Freno::Throttler.new(client: sample_client, app: :github)

    begin
      Timeout.timeout(0.1) do
        loop do
          throttler.throttle do
            result << enumerator.next
          end
        end
      end
    rescue Timeout::Error
      flunk "Throttling an enumerator caused an infinite loop."
    end

    assert_equal array, result
  end
end
