import numpy as np
import os

cimport numpy as cnp
from libc.string cimport memcpy

from gnome import basic_types

from type_defs cimport *
from utils cimport _NewHandle, _GetHandleSize
from utils cimport OSSMTimeValue_c
from cy_helpers import filename_as_bytes


cdef class CyOSSMTime(object):

    # underlying C++ object that is instantiated
    # declared in pxd file
    #cdef OSSMTimeValue_c * time_dep
    #cdef object _user_units_dict
    def __cinit__(self):
        if type(self) == CyOSSMTime:
            self.time_dep = new OSSMTimeValue_c()
        else:
            self.time_dep = NULL

        # Define user units for velocity. In C++, these are #defined as
        self._user_units_dict = {-1: 'undefined',
                                 1: 'knots',
                                 2: 'meters per second',
                                 3: 'miles per hour'}

        # initialize this in init function
        self._file_format = 0

    def __dealloc__(self):
        if self.time_dep is not NULL:
            del self.time_dep

    def __init__(self, basestring filename=None, int file_format=0,
                 cnp.ndarray[TimeValuePair, ndim=1] timeseries=None,
                 scale_factor=1):
        """
        Initialize object - takes either file or time value pair to initialize

        :param basestring filename: path to file containing time series data.
            It valid user_units are defined in the file, it uses them;
            otherwise, it defaults the user_units to meters_per_sec.
        :param int file_format: one of the values defined by enum type,
            gnome.basic_types.ts_format
        :param ndarray timeseries: numpy array containing time series data in
            time_value_pair structure as defined in type_defs
            If both are given, it will read data from the file
        :param int scale_factor: The timeseries is scaled by this constant

        .. note::

        * If timeseries are given, and data is velocity, it is always
          assumed to be in meters_per_sec and in 'uv' format
        * If neither file, nor timeseries are given, then set timeseries to
          zeros. The user_units are only set when read from file - else they
          are left as 'undefined'
        * The _file_format property is set even when timeseries are entered
          just for completeness; however, it is always 'uv' format for
          timeseries

        """
        if (filename is None or filename == "") and (timeseries is None):
            timeseries = np.zeros((1,), dtype=basic_types.time_value_pair)

        # type of data contained in file, 'uv' or 'r-theta' format
        if filename is not None:
            if not os.path.exists(filename):
                raise IOError("No such file: " + filename)

            self._file_format = file_format
            self._read_time_values(filename)
        else:
            self._set_time_value_handle(timeseries)
            self._file_format = basic_types.ts_format.uv
            # UserUnits for velocity assumed to be meter per second.
            # Leave undefined because the timeseries could be something
            # other than velocity.
            # TODO: check if OSSMTimeValue_c is only used for velocity data?
            self.time_dep.SetUserUnits(-1)
        self.time_dep.fScaleFactor = scale_factor

    property user_units:
        def __get__(self):
            '''
            These are the units for the data as it originally was read in from
            the file. Once data is read, it is converted to MKS units and this
            is never used. It is also not settable since it is set by C++ only
            upon file read. When setting the timeseries from a numpy data
            array, we always assume the data is in MKS units - no conversion
            happens in cython code
            '''
            try:
                return self._user_units_dict[self.time_dep.GetUserUnits()]
            except KeyError:
                raise ValueError('C++ GetUserUnits() gave a result which is '
                                 'outside the expected bounds.')

    property timeseries:
        def __get__(self):
            """
            returns the time series stored in the OSSMTimeValue_c object.
            It returns a memcpy of it.
            """
            return self._get_time_value_handle()

        def __set__(self, value):
            self._set_time_value_handle(value)

    property filename:
        def __get__(self):
            return <bytes>self.time_dep.filePath

    property scale_factor:
        def __get__(self):
            return self.time_dep.fScaleFactor

        def __set__(self, value):
            self.time_dep.fScaleFactor = value

    property station_location:
        def __get__(self):
            #return np.array((0, 0, 0), dtype=basic_types.world_point)
            """ get station location as read from file """
            cdef cnp.ndarray[WorldPoint, ndim = 1] wp
            wp = np.zeros((1,), dtype=basic_types.w_point_2d)

            wp[0] = self.time_dep.GetStationLocation()
            wp['lat'][:] = wp['lat'][:] / 1.e6    # correct C++ scaling here
            wp['long'][:] = wp['long'][:] / 1.e6    # correct C++ scaling here

            g_wp = np.zeros((1,), dtype=basic_types.world_point)
            g_wp[0] = (wp['long'], wp['lat'], 0)

            return tuple(g_wp[0])

        def __set__(self, value):
            self.station_location = value

    property station:
        def __get__(self):
            """ get station name as read from SHIO file """
            cdef bytes sName
            sName = self.time_dep.fStationName
            return sName

    def __repr__(self):
        """
        Return an unambiguous representation of this object so it can be
        recreated.
        If this works properly, then eval(repr(<cy_ossm_time_obj>)) should
        product a copy of the CyOSSMTime object

        (Note: the timeseries is a numpy array, and if it gets really big,
               say 1000 elements or more, then the repr() will abbreviate,
               and the representation will be ambiguous and not reproducible.
               The way to increase this size threshold is with the command

               np.set_printoptions(threshold=<really_big_number>).

               But do we really want to do that?  One of our unit tests
               has nearly 30000 elements in the timeseries.)

        NOTE: this may fail with a unicode file name.
        """
        self_ts = self.timeseries.__repr__()
        return ('{0.__class__.__module__}.{0.__class__.__name__}('
                'filename=r"{0.filename}", '
                'file_format={0._file_format}, '
                'timeseries={1}'
                ')').format(self, self_ts)

    def __str__(self):
        """Return string info about the object"""
        return ('{0.__class__.__name__}'
                '(filename="{0.filename}", '
                'timeseries=<see timeseries attribute>)').format(self)

    def __reduce__(self):
        return (CyOSSMTime, (self.filename,
                             self._file_format,
                             self.timeseries,
                             self.scale_factor))

    def __eq(self, CyOSSMTime other):
        scalar_attrs = ('filename', '_file_format', 'scale_factor',
                        'station_location', 'user_units')
        vector_attrs = ('timeseries',)
        if not all([getattr(self, a) == getattr(other, a)
                    for a in scalar_attrs]):
            return False

        if not all([all(getattr(self, a) == getattr(other, a))
                    for a in vector_attrs]):
            return False

        return True

    def __richcmp__(self, CyOSSMTime other, int cmp):
        if cmp not in (2, 3):
            raise NotImplemented('CyOSSMTime does not support '
                                 'this type of comparison.')

        if cmp == 2:
            return self.__eq(other)
        elif cmp == 3:
            return not self.__eq(other)

    def get_time_value(self, modelTime):
        """
          GetTimeValue - for a specified modelTime or array of model times,
              it returns the values.
        """
        cdef cnp.ndarray[Seconds, ndim = 1] modelTimeArray
        modelTimeArray = np.asarray(modelTime,
                                    basic_types.seconds).reshape((-1,))

        # velocity record passed to OSSMTimeValue_c methods and
        # returned back to python
        cdef cnp.ndarray[VelocityRec, ndim = 1] vel_rec
        cdef VelocityRec * velrec

        cdef unsigned int i
        cdef OSErr err

        vel_rec = np.empty((modelTimeArray.size,),
                           dtype=basic_types.velocity_rec)

        for i in range(0, modelTimeArray.size):
            err = self.time_dep.GetTimeValue(modelTimeArray[i], &vel_rec[i])
            if err != 0:
                raise ValueError('Error invoking TimeValue_c.GetTimeValue '
                                 'method in CyOSSMTime: '
                                 'C++ OSERR = {0}'.format(err))

        return vel_rec

    def _read_time_values(self, filename):
        """
        For OSSMTimeValue_c().ReadTimeValues()
            Format for the data file. This is an enum type in C++
            defined below. These are defined in cy_basic_types such that
            python can see them.

            ==================================================================
            enum {M19REALREAL = 1,
                  M19HILITEDEFAULT,
                  M19MAGNITUDEDEGREES,
                  M19DEGREESMAGNITUDE,
                  M19MAGNITUDEDIRECTION,
                  M19DIRECTIONMAGNITUDE,
                  M19CANCEL,
                  M19LABEL};
            ==================================================================

            The default format is Magnitude and direction as defined for wind

            Units are defined by following integers:
                Undefined: -1
                Knots: 1
                MilesPerHour: 2
                MetersPerSec: 3

            Make this private since the constructor will likely call this
            when object is instantiated
        """
        file_ = filename_as_bytes(filename)

        if self._file_format not in basic_types.ts_format._int:
            raise ValueError('_file_format can only contain integers 5, '
                             'or 1; also defined by basic_types.ts_format.'
                             '<magnitude_direction or uv>')

        err = self.time_dep.ReadTimeValues(file_, self._file_format, -1)
        self._raise_errors(err)

    def _raise_errors(self, err):
        'Raise appropriate error'
        if err == 1:
            # TODO: need to define error codes in C++
            # and raise other exceptions
            raise ValueError("Valid user units not found in file")

        if err != 0:
            raise IOError('Error occurred in C++: '
                    '{0}().ReadTimeValues()'.format(self.__class__.__name__))

    def _set_time_value_handle(self,
                               cnp.ndarray[TimeValuePair, ndim=1] time_val):
        """
        Takes a numpy array containing a time series,
        copies it to a Handle (TimeValuePairH),
        then invokes the SetTimeValueHandle method of OSSMTimeValue_c object.
        Make this private since the constructor will likely call this when
        the object is instantiated
        """
        if time_val is None:
            raise TypeError("expected ndarray, NoneType found")

        cdef short tmp_size = sizeof(TimeValuePair)
        cdef TimeValuePairH time_val_hdlH

        time_val_hdlH = <TimeValuePairH>_NewHandle(time_val.nbytes)
        memcpy(time_val_hdlH[0], &time_val[0], time_val.nbytes)

        self.time_dep.SetTimeValueHandle(time_val_hdlH)

    def _get_time_value_handle(self):
        """
            Invokes the GetTimeValueHandle method of OSSMTimeValue_c object
            to read the time series data
        """
        cdef short tmp_size = sizeof(TimeValuePair)
        cdef TimeValuePairH time_val_hdlH
        cdef cnp.ndarray[TimeValuePair, ndim = 1] tval

        # allocate memory and copy it over
        time_val_hdlH = self.time_dep.GetTimeValueHandle()
        sz = _GetHandleSize(<Handle>time_val_hdlH)

        # will this always work?
        tval = np.empty((sz / tmp_size,), dtype=basic_types.time_value_pair)

        memcpy(&tval[0], time_val_hdlH[0], sz)
        return tval
