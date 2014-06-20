#encoding: utf-8
require 'fileutils'
require 'yaml'
require 'google_drive'

class Server
  attr_accessor :quizzes
  attr_reader :title, :data, :students, :teachers, :path_config
  
  def initialize(quizzes)
    @quiz = quizzes[0]
    @html = @quiz.output
    @data = @quiz.data
    @students = @quiz.users
    @teachers = @quiz.admins
    @path_config = @quiz.path_config
  end
  
  def make_server
    make_directories
    make_students_csv_rb
    make_teachers_rb
    make_config_yml
    make_data
    make_html
    make_gemfile
    make_rakefile
    make_config_ru
    make_layout
    make_login
    make_finish
    make_available
    make_initialize_quiz
    make_initialized
    make_not_initialized
    make_not_allowed
    make_app_rb
  end
  
  def make_directories
    #FileUtils::cd('../')              # Arreglar path para ejecutar desde la gema
    FileUtils::mkdir_p 'app/views'
    FileUtils::mkdir_p 'app/config'
  end
  
  def make_students_csv_rb
    if (@students.class == Symbol)
      FileUtils::cp File.expand_path(@students.to_s), 'app/config'
    elsif (@students.class == Hash)
      make_file(@students, 'app/config/students.rb')
    end
  end
  
  def make_teachers_rb
    if (@teachers.class == String)
      make_file(@teachers, 'app/config/teachers.rb')
    elsif (@teachers.class == Array)
      File.open('app/config/teachers.rb', 'w') do |f|
        @teachers.each { |teacher| f.puts(teacher)}
        f.close
      end
    end
  end
  
  def make_config_yml
    FileUtils::cp File.expand_path(@path_config.to_s), 'app/config'
    load_config_yml
  end
  
  def load_config_yml
    @config = YAML.load_file('app/config/config.yml')
    @title = @config["quiz"]["heroku"]["domain"] || @quiz.title
  end
  
  def make_data
    make_file(@data, 'app/config/data.rb')
  end
  
  def make_html
    make_file(@html, "app/views/#{@title}.html")
  end
  
  def make_app_rb
    content = %Q{#encoding: utf-8
require 'sinatra/base'
require 'omniauth'
require 'omniauth-google-oauth2'
require 'yaml'
require 'csv'
require 'google_drive'

class MyApp < Sinatra::Base
  
  configure do
    enable :logging, :dump_errors
    disable :show_exceptions
    set :raise_errors, false
    set :session_secret, '#{@title.crypt(@title)}'
    enable :protection
    set :server, 'webrick'
    set :timeout, 300
  end
  
  use Rack::Session::Pool
  
  helpers do
    
    def store_students(path, type)
      if (type == 'csv')
        hash = {}
        CSV.foreach(path) do |row|
          hash[row[0].to_sym] = {:surname => row[1].lstrip, :name => row[2].lstrip.chomp}
        end
        hash
      elsif (type == 'rb')
        eval(path)
      end
    end
    
    def store_teachers(path)
      people = []
      File.open(path, 'r') do |f|
        while line = f.gets
          people << line
        end
        f.close
      end
      people
    end
    
    def load_config_yml
      $config = YAML.load_file('config/config.yml')
    end
    
    def calculate_time(type)
      date = $config["quiz"]["schedule"][("date_" + type)].split('-')
      time = $config["quiz"]["schedule"][("time_" + type)].split(':')
      Time.new(date[0], date[1], date[2], time[0], time[1]).getutc.to_i
    end
    
    def before_available
      start_utc_seconds = calculate_time('start')
      
      if (Time.now.getutc.to_i < start_utc_seconds)
        return true
      else
        return false
      end
    end
    
    def after_available
      finish_utc_seconds = calculate_time('finish')
      
      if (Time.now.getutc.to_i > finish_utc_seconds)
        return true
      else
        return false
      end
    end
    
    def find(h, answers)
      if (h.respond_to?('keys'))
        h.each_key do |k|
          if ((k.to_s =~ /^qfi/) || (k.to_s =~ /^qmc/) || (k.to_s =~ /^qsm/) || (k.to_s =~ /^qdd/) || (k.to_s =~ /^qp/))
            if (h[k][:correct] == true)
              $ids_answers << k.to_s
              answers << h[k][:answer_text]
            end
          end
          find(h[k], answers)
        end
      end
    end
    
    def google_login(token)
      begin
        GoogleDrive.login_with_oauth(token)
      rescue Exception => e
        $stderr.puts e.message
        exit
      end
    end
    
    def get_spreadsheet(file)
      $session.spreadsheet_by_url(file.worksheets_feed_url)
    end
    
    def type_question(key)
      if (key =~ /qfi/)
        type = "FillIn" 
      elsif (key =~ /qddfi/)
        type = "Drag and Drop FillIn"
      elsif (key =~ /qp/)
        type = "Programming"
      elsif (key =~ /qmc/)
        type = "Multiple Choice"
      elsif (key =~ /qddmc/)
        type = "Drag and Drop Multiple Choice"
      elsif (key =~ /qsm/)
        type = "Select Multiple"
      elsif (key =~ /qddsm/)
        type = "Drag and Drop Select Multiple"
      end
    end
    
    def write_spreadsheet_teacher(file)
      $spreadsheet = get_spreadsheet(file)
      worksheet = $spreadsheet.worksheets[0]
      worksheet.title = $config["quiz"]["google_drive"]["spreadsheet_name"]
      %w{Email Apellidos Nombre Nota Examen}.each_with_index { |value, index| worksheet[1, index + 1] = value }
      $id_students = {}
      $students.each_with_index do |k, i|
        key = k[0]
        value = k[1]
        worksheet[i + 2, 1] = key.to_s
        worksheet[i + 2, 2] = value[:surname]
        worksheet[i + 2, 3] = value[:name]
        
        username = key.to_s.split('@')[0]
        $id_students[username.to_sym] = i
      end
      
      # Save changes and reload spreadsheet
      worksheet.save()
      worksheet.reload()
      
      # New worksheet (questions' id and questions' text)
      if ($spreadsheet.worksheet_by_title("Preguntas") == nil)
        $spreadsheet.add_worksheet("Preguntas", 1000, 24)
      end
      worksheet = $spreadsheet.worksheets[1]
      %w{ID_Pregunta Tipo_Pregunta Pregunta}.each_with_index { |value, index| worksheet[1, index + 1] = value }
      $data.keys.each_with_index do |value, index| 
        worksheet[index + 2, 1] = value
        worksheet[index + 2, 2] = type_question($data[value][:answers].keys[0].to_s)
        worksheet[index + 2, 3] = $data[value][:question_text]
      end
      
      # Save changes and reload spreadsheet
      worksheet.save()
      worksheet.reload()
      
      # New worksheet (answers' id and answers' text)
      if ($spreadsheet.worksheet_by_title("Respuestas") == nil)
        $spreadsheet.add_worksheet("Respuestas", 1000, 24)
      end
      worksheet = $spreadsheet.worksheets[2]
      %w{ID_Respuesta Respuesta}.each_with_index { |value, index| worksheet[1, index + 1] = value }
      $ids_answers, answers = [], []
      find($data, answers)
      $ids_answers.each_with_index { |value, index| worksheet[index + 2, 1] = value }
      answers.each_with_index { |value, index| worksheet[index + 2, 2] = value }
      
      # Save changes and reload spreadsheet
      worksheet.save()
      worksheet.reload()
      
      # Return human URL of Google Drive Spreadsheet
      $spreadsheet.human_url
    end
    
    def create_folder
      root_folder = $session.root_collection
      if ($config["quiz"]["google_drive"].key?("path"))
        local_root = root_folder
        folders = $config["quiz"]["google_drive"]["path"].split('/')
        folders.each do |folder|
          if (local_root.subcollection_by_title(folder) == nil)
            local_root.create_subcollection(folder)
            local_root = local_root.subcollection_by_title(folder)
          else
            local_root = local_root.subcollection_by_title(folder)
          end
        end
        if (local_root.subcollection_by_title($config["quiz"]["google_drive"]["folder"]) == nil)
          local_root.create_subcollection($config["quiz"]["google_drive"]["folder"])
        else
          local_root = local_root.subcollection_by_title($config["quiz"]["google_drive"]["folder"])
        end
      else
        root_folder.create_subcollection($config["quiz"]["google_drive"]["folder"]) if root_folder.subcollection_by_title($config["quiz"]["google_drive"]["folder"]) == nil
      end
    end
    
    def upload_copy_quiz(user=nil)
      if (user == nil)
        name = "#{@title}.html"
      else
        name = "#{@title} - " + user + ".html"
      end
      
      # If a student already post a quiz or a teacher generate again the quiz, it will be removed
      if ($session.file_by_title(name) != nil)
        $session.file_by_title(name).delete(true)
      end
      
      # if de si sera un html con las respuestas del alumno (para tratarlo) o la copia original del profesor
      
      # Upload a HTML quiz with the students answers
      file = $session.upload_from_file("views/#{@title}.html", name, :convert => false)
      $dest.add(file)
      $session.root_collection.remove(file)
    end
    
    def drive(token)
      $session = google_login(token)
      $dest = create_folder
      $id_folder = $dest.resource_id.to_s.split(':')[1]
      
      # Upload a copy of the HTML Quiz to the specified folder ($dest)
      upload_copy_quiz
      
      # Create or get spreadsheet
      if ($session.spreadsheet_by_title($config["quiz"]["google_drive"]["spreadsheet_name"]) == nil)
        file = $session.create_spreadsheet($config["quiz"]["google_drive"]["spreadsheet_name"])
        $dest.add(file)
        $session.root_collection.remove(file)
      else
        file = $session.spreadsheet_by_title($config["quiz"]["google_drive"]["spreadsheet_name"])
      end
      write_spreadsheet_teacher(file)
    end
    
    def write_worksheet_student(user)
      # Get or create student worksheet
      worksheet = $spreadsheet.worksheet_by_title(user)
      if (worksheet == nil)
        worksheet = $spreadsheet.add_worksheet(user, 1000, 24)
      end
      
      # Write student worksheet
      %w{ID_Pregunta Puntuación}.each_with_index { |value, index| worksheet[1, index + 1] = value }
      $data.keys.each_with_index { |value, index| worksheet[index + 2, 1] = value }
    
      # Save changes and reload worksheet
      worksheet.save()
      worksheet.reload()
    end
    
    def write_mark_worksheet_teacher(user)
      # Get the teacher worksheet
      worksheet = $spreadsheet.worksheet_by_title($config["quiz"]["google_drive"]["spreadsheet_name"])
      
      # Write the mark and the URL of the student's quiz
      worksheet[$id_students[user.to_sym] + 2, 4] = "NOTA"
      worksheet[$id_students[user.to_sym] + 2, 5] = $session.file_by_title("#{@title} - " + user + ".html").human_url
      
      # Save changes and reload worksheet
      worksheet.save()
      worksheet.reload()
    end
    
    def evaluate(user, answers)
      # Validar respuestas (pendiente)
      # html -> split('<form ')[1]
      # -> split('</form>')[0]
      # Ahora tenemos todo el form
      # -> scan(/<input .*/) || scan(/<input(\s?.*)/)
      # Faltaria obtener preguntas de codigo
      
      write_worksheet_student(user)
      upload_copy_quiz(user)
      write_mark_worksheet_teacher(user)
    end
  end
  
  $data = eval(File.read('config/data.rb'))
  $initialized = false
  $active = false
  
  get '/' do
    load_config_yml if ((!$initialized) && (!$active))
    if (before_available)
      date = $config["quiz"]["schedule"]["date_start"].split('-')
      time = $config["quiz"]["schedule"]["time_start"]
      erb :available, :locals => {:state => 'not started', :title => '#{@title}', :date => [date[2], date[1], date[0]].join('/'), :time => time}
    elsif (after_available)
      date = $config["quiz"]["schedule"]["date_finish"].split('-')
      time = $config["quiz"]["schedule"]["time_finish"]
      erb :available, :locals => {:state => 'finished', :title => '#{@title}', :date => [date[2], date[1], date[0]].join('/'), :time => time}
    else
      if ((session[:student]) || (session[:teacher]))
        send_file 'views/#{@title}.html'
      else
        erb :login, :locals => {:title => "Autenticación"}
      end
    end
  end

  get '/quiz' do
    if ((session[:teacher]) || (session[:student]))
      send_file 'views/#{@title}.html'
    else
      redirect '/'
    end
  end
  
  post '/quiz' do
    if (session[:student])
      teacher = false
      user = session[:student].split('@')[0]
      evaluate(user, params)
    else
      teacher = true
    end
    date = $config["quiz"]["schedule"]["date_finish"].split('-')
    time = $config["quiz"]["schedule"]["time_finish"]
    erb :finish, :locals => {:title => "Finalizar", :quiz_name => '#{@title}', :date => [date[2], date[1], date[0]].join('/'), :time => time, :teacher => teacher, :id_folder => $id_folder}
  end
  
  get '/logout' do
    session.clear
    redirect '/'
  end
  
  get '/initialized' do
    if (($initialized) && (!$active))
      $active = true
      url = drive($token)
      erb :initialized, :locals => {:title => "Cuestionario inicializado", :url => url, :name => $config["quiz"]["google_drive"]["spreadsheet_name"]}
    else
      redirect '/'
    end
  end
  
  get '/not_initialized' do
    erb :not_initialized, :locals => {:title => "Cuestionario no disponible"}
  end
  
  get '/auth/:provider/callback' do
    response = request.env['omniauth.auth'].to_hash
    if (!$initialized)
      load_config_yml
      $teachers = store_teachers('config/teachers.rb')
      if (File.exist?('config/students.csv'))
        $students = store_students('config/students.csv', 'csv')
      elsif (File.exist?('config/students.rb'))
        $students = store_students('config/students.rb', 'rb')
      end
      if ($teachers.include?(response['info']['email']))
        session[:teacher] = response['info']['email']
        $token = response['credentials']['token']
        $initialized = true
        erb :initialize_quiz, :locals => {:title => "Activar cuestionario"}
      else
        redirect '/not_initialized'
      end
    else
      if ($teachers.include?(response['info']['email']))
        session[:teacher] = response['info']['email']
        redirect '/quiz'
      else
        if ($students.key?(response['info']['email'].to_sym))
          session[:student] = response['info']['email']
          redirect '/quiz'
        else
          erb :not_allowed, :locals => {:title => "No permitido"}
        end
      end
    end
  end
  
  use OmniAuth::Builder do
    config = YAML.load_file('config/config.yml')
    provider :google_oauth2, config["quiz"]["google_drive"]["google_key"], config["quiz"]["google_drive"]["google_secret"], {
      :scope => 
        "email " +
        "profile " +
        "https://docs.google.com/feeds/ " +
        "https://docs.googleusercontent.com/ " +
        "https://spreadsheets.google.com/feeds/"
    }
  end

  # Start the server if the ruby file is executed
  run! if app_file == $0
  
end}
    name = 'app/app.rb'
    make_file(content, name)
  end
  
  def make_config_ru
    content = %q{require './app'
run MyApp}
    name = 'app/config.ru'
    make_file(content, name)
  end
  
  def make_gemfile
    content = %q{source "http://rubygems.org"
gem 'sinatra'
gem 'google_drive'
gem 'omniauth'
gem 'omniauth-google-oauth2'}
    name = 'app/Gemfile'
    make_file(content, name)
  end
  
  def make_rakefile
    content = %Q{task :default => :build
    
desc "Generate Gemfile.lock"
task :bundle do
  sh "bundle install"
end

desc "Create local git repository"
task :git do
  sh "git init"
  sh "git add ."
  sh %q{git commit -m "Creating quiz"}
end

desc "Deploy to Heroku"
task :heroku do
  sh "heroku create --stack cedar #{@title.downcase.gsub(/\W/, '-')}"
  sh "git push heroku master"
end

desc "Build all"
task :build do
  [:bundle, :git, :heroku].each { |task| Rake::Task[task].execute }
end

desc "Run local server"
task :run do
  sh "ruby app.rb"
end}
    name = 'app/Rakefile'
    make_file(content, name)
  end
  
  def make_layout
    content = %q{<html lang="es">
  <head>
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <!-- Latest compiled and minified CSS -->
    <link rel="stylesheet" href="//netdna.bootstrapcdn.com/bootstrap/3.1.1/css/bootstrap.min.css">
    <style type="text/css">
      /* Signin */
      body{padding-top:40px;padding-bottom:40px;background-color:#eee}.form-signin{max-width:330px;padding:15px;margin:0 auto}.form-signin .checkbox,.form-signin .form-signin-heading{margin-bottom:10px}.form-signin .checkbox{font-weight:400}.form-signin .form-control{position:relative;height:auto;-webkit-box-sizing:border-box;-moz-box-sizing:border-box;box-sizing:border-box;padding:10px;font-size:16px}.form-signin .form-control:focus{z-index:2}.form-signin input[type=email]{margin-bottom:-1px;border-bottom-right-radius:0;border-bottom-left-radius:0}.form-signin input[type=password]{margin-bottom:10px;border-top-left-radius:0;border-top-right-radius:0}
      /* Sticky footer navbar */
      html{position:relative;min-height:100%}body{margin-bottom:60px}#footer{position:absolute;bottom:0;width:100%;height:60px;background-color:#f5f5f5}body>.container{padding:60px 15px 0}.container .text-muted{margin:20px 0}#footer>.container{padding-right:15px;padding-left:15px}code{font-size:80%}
      /* Jumbotron narrow */
      body{padding-top:20px;padding-bottom:20px}.footer,.header,.marketing{padding-right:15px;padding-left:15px}.header{border-bottom:1px solid #e5e5e5}.header h3{padding-bottom:19px;margin-top:0;margin-bottom:0;line-height:40px}.footer{padding-top:19px;color:#777;border-top:1px solid #e5e5e5}@media (min-width:768px){.container{max-width:730px}}.container-narrow>hr{margin:30px 0}.jumbotron{text-align:center;border-bottom:1px solid #e5e5e5}.jumbotron .btn{padding:14px 24px;font-size:21px}.marketing{margin:40px 0}.marketing p+h4{margin-top:28px}@media screen and (min-width:768px){.footer,.header,.marketing{padding-right:0;padding-left:0}.header{margin-bottom:30px}.jumbotron{border-bottom:0}}
    </style>
    <title><%= title %></title>
    <!-- HTML5 shim and Respond.js IE8 support of HTML5 elements and media queries -->
    <!--[if lt IE 9]>
      <script src="https://oss.maxcdn.com/libs/html5shiv/3.7.0/html5shiv.js"></script>
      <script src="https://oss.maxcdn.com/libs/respond.js/1.4.2/respond.min.js"></script>
    <![endif]-->
  </head>
  <body>
    <div class="container">
      <%= yield %>
    </div>
    <!-- jQuery (necessary for Bootstrap's JavaScript plugins) -->
    <script src="https://code.jquery.com/jquery-1.11.1.min.js"></script>
    <!-- Latest compiled and minified JavaScript -->
    <script src="//netdna.bootstrapcdn.com/bootstrap/3.1.1/js/bootstrap.min.js"></script>
  </body>
</html>}
    name = 'app/views/layout.erb'
    make_file(content, name)
  end
  
  def make_login
    content = %q{<div class="jumbotron">
  <h1>Autenticaci&oacute;n</h1>
  <div class="alert alert-info">
    Para acceder al cuestionario, por favor, inicie sesi&oacute;n con su cuenta de <strong>Google</strong>.
    Si no dispone de una, haga click <strong><a href="http://accounts.google.com/SignUp?service=mail" target="_blank">aqu&iacute;</a></strong> para crearla.
  </div>
  <a href='/auth/google_oauth2' class="btn btn-primary">Iniciar sesi&oacute;n</a>
  <br>
</div>}
    name = 'app/views/login.erb'
    make_file(content, name)
  end
  
  def make_finish
    content = %q{<div class="jumbotron">
  <% if (teacher) %>
    <h2>Finalizar revisi&oacute;n</h2>
    <br />
    <a href="/" class="btn btn-info">Volver al cuestionario</a>
    <a href="https://drive.google.com/?usp=chrome_app#folders/<%= id_folder %>" class="btn btn-success" target="_blank">Ver Google Drive</a>
  <% else %>
    <h2>Respuestas guardadas</h2>
    <div class="alert alert-success">
      Ha finalizado el cuestionario y sus respuestas han sido guardadas correctamente.
      El cuestionario seguir&aacute; abierto hasta el <%= date %> a las <%= time %>. 
      Puede reintentar el mismo todas las veces que desee antes de la fecha l&iacute;mite.
    </div>
    <br />
    <a href="/logout" class="btn btn-danger">Cerrar sesi&oacute;n</a>
  <% end %>
</div>}
    name = 'app/views/finish.erb'
    make_file(content, name)
  end
  
  def make_available
    content = %q{<div class="jumbotron">
  <h1><%= title %></h1>
  <br />
  <% if (state == 'not started') %>
    <div class="alert alert-warning">
      El cuestionario se abrir&aacute; el <%= date %> a las <%= time %> horas.
      Vuelva en ese momento para poder realizarlo.
    </div>
  <% else %>
    <div class="alert alert-danger">
      El cuestionario se cerr&oacute; el <%= date %> a las <%= time %> horas.
      Ya no es posible realizar ning&uacute;n env&iacute;o.
    </div>
  <% end %>
</div>}
    name = 'app/views/available.erb'
    make_file(content, name)
  end
  
  def make_initialized
    content = %q{<div class="jumbotron">
  <h1><%= title %></h1>
  <br />
  <div class="alert alert-success">
    El cuestionario ha sido inicializado correctamente. Puede consultar la hoja de
    c&aacute;lculo generada pulsando en el siguente enlace: <a href="<%= url %>" target="_blank"><%= name %></a>.
  </div>
  <a href="/" class="btn btn-primary">Volver al cuestionario</a>
</div>}
    name = 'app/views/initialized.erb'
    make_file(content, name)
  end
  
  def make_not_initialized
    content = %q{<div class="jumbotron">
  <h1><%= title %></h1>
  <br />
  <div class="alert alert-danger">
    El cuestionario a&uacute;n no est&aacute; activado. Por favor, vuelva m&aacute;s tarde. 
  </div>
</div>}
    name = 'app/views/not_initialized.erb'
    make_file(content, name)
  end
  
  def make_initialize_quiz
    content = %q{<div class="jumbotron">
  <h1><%= title %></h1>
  <br />
  <div class="alert alert-warning">
    Para activar el cuestionario haga click en el siguiente bot&oacute;n. 
    Tenga en cuenta que esta tarea puede tardar unos minutos.
  </div>
  <a href="/initialized" class="btn btn-warning">Activar cuestionario</a>
</div>}
    name = 'app/views/initialize_quiz.erb'
    make_file(content, name)
  end
  
  def make_not_allowed
    content = %q{<div class="jumbotron">
  <h1><%= title %></h1>
  <br />
  <div class="alert alert-danger">
    No dispone de permisos para realizar este cuestionario. Para m&aacute;s informaci&oacute;n, contacte con su profesor.
  </div>
</div>}
    name = 'app/views/not_allowed.erb'
    make_file(content, name)
  end
  
  def make_file(content, name)
    File.open(name, 'w') do |f|
      f.write(content)
      f.close
    end
  end
  
end