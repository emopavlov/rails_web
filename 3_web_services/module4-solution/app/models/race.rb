class Race
  include Mongoid::Document
  include Mongoid::Timestamps

  DEFAULT_EVENTS = {"swim"=>{:order=>0, :name=>"swim", :distance=>1.0, :units=>"miles"},
    "t1"=> {:order=>1, :name=>"t1"},
    "bike"=>{:order=>2, :name=>"bike", :distance=>25.0, :units=>"miles"},
    "t2"=> {:order=>3, :name=>"t2"},
    "run"=> {:order=>4, :name=>"run", :distance=>10.0, :units=>"kilometers"}}

  field :n, as: :name, type: String
  field :date, type: Date
  field :loc, as: :location, type: Address
  field :next_bib, type: Integer, default: 0

  embeds_many :events, class_name: 'Event', as: :parent, order: [:order.asc]
  has_many :entrants, foreign_key: "race._id", dependent: :delete, order: [:secs.asc, :bib.asc]

  scope :upcoming, ->{ where(:date.gte => Date.today) }
  scope :past, ->{ where(:date.lt => Date.today) }

  DEFAULT_EVENTS.keys.each do |name|
    define_method("#{name}") do
      event=events.select {|event| name==event.name}.first
      event||=events.build(DEFAULT_EVENTS["#{name}"])
    end

    ["order","distance","units"].each do |prop|
      if DEFAULT_EVENTS["#{name}"][prop.to_sym]
        define_method("#{name}_#{prop}") do
          self.send("#{name}").send("#{prop}")
        end
        define_method("#{name}_#{prop}=") do |value|
        end
      end
    end
  end

  def self.default
    Race.new do |race|
      DEFAULT_EVENTS.keys.each {|leg| race.send("#{leg}")}
    end
  end

  ["city", "state"].each do |action|
    define_method("#{action}") do
      self.location ? self.location.send("#{action}") : nil
    end

    define_method("#{action}=") do |name|
      object=self.location ||= Address.new
      object.send("#{action}=", name)
      self.location=object
    end
  end

  def next_bib
    inc(next_bib: 1)[:next_bib]
  end

  def get_group racer
    if racer && racer.birth_year && racer.gender
      quotient=(date.year-racer.birth_year)/10
      min_age=quotient*10
      max_age=((quotient+1)*10)-1
      gender=racer.gender
      name=min_age >= 60 ? "masters #{gender}" : "#{min_age} to #{max_age} (#{gender})"
      Placing.demongoize(:name=>name)
    end
  end

  def create_entrant racer
    entrant = Entrant.new
    entrant.build_race(self.attributes.symbolize_keys.slice(:_id, :n, :date))
    entrant.build_racer(racer.info.attributes)
    entrant.group = get_group(racer)
    self.events.each do |event|
      entrant.send("#{event.name}=", event)
    end
    entrant.validate
    if entrant.valid?
      entrant.bib = self.next_bib
      entrant.save
    end
    entrant
  end

  def self.upcoming_available_to racer
    racer_race_registration_ids = Entrant.collection.aggregate([
      {:$match => {:"racer.racer_id" => racer.id}},
      {:$project => {"race._id" => 1,}},
      {:$group => {:_id => "$race._id"}}
    ]).to_a.map {|h| h[:_id]}

    upcoming.where({:_id => { :$nin => racer_race_registration_ids }})
  end
end
